# frozen_string_literal: true

require "json"

module RecordingStudioMcp
  # Cross-process MCP subscription fan-out via Postgres LISTEN/NOTIFY.
  #
  # The listen thread is started only in long-lived server or worker processes.
  # Rake tasks, rails console, and rails runner skip it unless
  # RECORDING_STUDIO_MCP_POSTGRES_BUS=1 is set. Set that same variable to 0 to
  # force the bus off in a server process.
  module PostgresBus
    CHANNEL = "recording_studio_mcp_events"
    START_ENV = "RECORDING_STUDIO_MCP_POSTGRES_BUS"
    STOP_JOIN_TIMEOUT = 5
    WAIT_TIMEOUT_SECONDS = 1
    RECONNECT_BASE_SECONDS = 0.5
    RECONNECT_MAX_SECONDS = 5
    WARN_INTERVAL_SECONDS = 5
    START_ON = %w[1 true yes].freeze
    START_OFF = %w[0 false no].freeze

    module_function

    def enabled?
      return false unless defined?(ActiveRecord::Base)
      return false unless ActiveRecord::Base.connected?

      ActiveRecord::Base.connection.adapter_name.match?(/postg/i)
    rescue StandardError
      false
    end

    # Whether this process should open a LISTEN thread on boot.
    # Public Rails signals only: Console, Rake top-level tasks,
    # Rails::Command::RunnerCommand (loaded before boot_application! for
    # `rails runner` — ARGV no longer contains "runner" by then), plus START_ENV.
    def start_allowed?
      override = env_start_override
      return override unless override.nil?

      !(rails_console? || rake_task? || rails_runner?)
    end

    def publish(event_name:, recording_id:)
      payload = JSON.generate({ "event" => event_name.to_s, "id" => recording_id.to_s })
      quoted = ActiveRecord::Base.connection.quote(payload)
      ActiveRecord::Base.connection.execute("NOTIFY #{CHANNEL}, #{quoted}")
    end

    def listening?
      mutex.synchronize { @thread&.alive? == true }
    end

    def start!
      return unless enabled?
      return unless start_allowed?

      mutex.synchronize do
        return if @thread&.alive?

        @owner_pid = Process.pid
        register_shutdown_hook!
        @running = true
        @thread = Thread.new { listen_loop }
      end
    end

    # Signal the LISTEN loop to exit, wake it, join the thread, then release the
    # dedicated connection. Safe to call more than once. If the join times out,
    # the connection is left alone — the thread may still be using it.
    def stop!
      thread = nil
      mutex.synchronize do
        @running = false
        thread = @thread
        @thread = nil
      end

      wake_listen_loop
      return if thread.nil?

      finished = thread.join(STOP_JOIN_TIMEOUT)
      if finished.nil? && thread.alive?
        log_warn("listen thread did not stop within #{STOP_JOIN_TIMEOUT}s; " \
                 "leaving connection for process exit")
        return
      end

      release_listen_connection
    end

    def handle_payload(payload)
      data = JSON.parse(payload.to_s)
      event_name = data["event"]
      recording_id = data["id"]
      return if event_name.blank? || recording_id.blank?

      Notifier.deliver_local(event_name: event_name, recording_id: recording_id)
    rescue StandardError
      nil
    end

    def mutex
      @mutex ||= Mutex.new
    end
    private_class_method :mutex

    def env_start_override
      flag = ENV.fetch(START_ENV, nil)&.strip&.downcase
      return true if START_ON.include?(flag)
      return false if START_OFF.include?(flag)

      nil
    end
    private_class_method :env_start_override

    def rails_console?
      defined?(Rails) && Rails.const_defined?(:Console)
    end
    private_class_method :rails_console?

    def rake_task?
      defined?(Rake) &&
        Rake.respond_to?(:application) &&
        Rake.application&.top_level_tasks&.any?
    end
    private_class_method :rake_task?

    # railties 8.1 RunnerCommand#perform calls boot_application! after the
    # command class is loaded; commands.rb has already shifted "runner" off ARGV.
    def rails_runner?
      defined?(Rails::Command::RunnerCommand)
    end
    private_class_method :rails_runner?

    def register_shutdown_hook!
      return if @shutdown_hook_registered

      @shutdown_hook_registered = true
      # at_exit runs LIFO: register after ActiveRecord so we stop before it
      # disconnects the pool on process exit. Skip in forked children.
      at_exit { shutdown_if_owner! }
    end
    private_class_method :register_shutdown_hook!

    def shutdown_if_owner!
      return unless @owner_pid == Process.pid

      stop!
    end
    private_class_method :shutdown_if_owner!

    def listen_loop
      attempts = 0
      while running?
        begin
          raw = open_listen_socket
          # Reset attempts only after a successful wait, not merely on reconnect.
          attempts = poll_notifications(raw, attempts)
        rescue StandardError => e
          raise unless listen_recoverable_error?(e)

          handle_listen_failure(e, attempts)
          break unless running?

          attempts += 1
          break unless reconnect_after_failure?(attempts)
        end
      end
    ensure
      release_listen_connection
    end
    private_class_method :listen_loop

    def handle_listen_failure(error, attempts)
      log_warn_rate_limited(
        :listen_failure,
        "LISTEN failed (attempt #{attempts + 1}): #{error.class}: #{error.message}"
      )
      release_listen_connection
    end
    private_class_method :handle_listen_failure

    # Retry indefinitely with exponential backoff capped at RECONNECT_MAX_SECONDS
    # until stop! clears @running.
    def reconnect_after_failure?(attempts)
      delay = reconnect_delay(attempts)
      log_warn_rate_limited(
        :reconnect,
        "LISTEN reconnecting in #{delay}s (attempt #{attempts})"
      )
      interruptible_sleep(delay)
      running?
    end
    private_class_method :reconnect_after_failure?

    def reconnect_delay(attempts)
      # 0.5 * 2^3 = 4; 0.5 * 2^4 = 8 > 5s cap. Avoid huge exponents.
      return RECONNECT_MAX_SECONDS if attempts >= 5

      RECONNECT_BASE_SECONDS * (2**(attempts - 1))
    end
    private_class_method :reconnect_delay

    def interruptible_sleep(seconds)
      deadline = monotonic_now + seconds
      while running?
        remaining = deadline - monotonic_now
        break if remaining <= 0

        sleep_wait([remaining, 0.1].min)
      end
    end
    private_class_method :interruptible_sleep

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    private_class_method :monotonic_now

    def sleep_wait(seconds)
      sleep(seconds)
    end
    private_class_method :sleep_wait

    def open_listen_socket
      connection = listen_connection
      connection.execute("LISTEN #{CHANNEL}")
      connection.raw_connection
    end
    private_class_method :open_listen_socket

    # Returns the updated attempts counter. A successful wait_for_notify resets it.
    def poll_notifications(raw, attempts)
      while running?
        wait_once(raw)
        attempts = 0
      end
      attempts
    end
    private_class_method :poll_notifications

    def wait_once(raw)
      raw.wait_for_notify(WAIT_TIMEOUT_SECONDS) do |_channel, _pid, payload|
        handle_payload(payload)
      end
    end
    private_class_method :wait_once

    def running?
      mutex.synchronize { @running == true }
    end
    private_class_method :running?

    def wake_listen_loop
      return unless defined?(ActiveRecord::Base)
      return unless ActiveRecord::Base.connected?

      ActiveRecord::Base.connection.execute("NOTIFY #{CHANNEL}")
    rescue StandardError
      nil
    end
    private_class_method :wake_listen_loop

    def listen_connection
      mutex.synchronize do
        @listen_connection ||= ActiveRecord::Base.connection_pool.checkout
      end
    end
    private_class_method :listen_connection

    # Idempotent. Never exec on a dead connection: skip UNLISTEN when the
    # socket is already gone, and rescue IOError/PG::Error so rake exit cannot
    # turn a closed stream into a segfault path through the adapter.
    def release_listen_connection
      connection = nil
      mutex.synchronize do
        connection = @listen_connection
        @listen_connection = nil
      end
      return if connection.nil?

      unlisten_if_alive(connection)
      checkin_or_disconnect(connection)
    end
    private_class_method :release_listen_connection

    def unlisten_if_alive(connection)
      return unless connection_usable?(connection)

      connection.execute("UNLISTEN #{CHANNEL}")
    rescue StandardError
      nil
    end
    private_class_method :unlisten_if_alive

    def connection_usable?(connection)
      return false unless connection

      raw = connection.raw_connection
      return false if raw.nil? || finished_raw?(raw) || inactive_connection?(connection)

      true
    rescue StandardError
      false
    end
    private_class_method :connection_usable?

    def finished_raw?(raw)
      raw.respond_to?(:finished?) && raw.finished?
    end
    private_class_method :finished_raw?

    def inactive_connection?(connection)
      connection.respond_to?(:active?) && !connection.active?
    end
    private_class_method :inactive_connection?

    def checkin_or_disconnect(connection)
      ActiveRecord::Base.connection_pool.checkin(connection)
    rescue StandardError
      begin
        connection.disconnect!
      rescue StandardError
        nil
      end
    end
    private_class_method :checkin_or_disconnect

    def listen_recoverable_error?(error)
      return true if error.is_a?(IOError)
      return true if defined?(PG::Error) && error.is_a?(PG::Error)
      return true if defined?(ActiveRecord::ActiveRecordError) && error.is_a?(ActiveRecord::ActiveRecordError)

      false
    end
    private_class_method :listen_recoverable_error?

    def log_warn_rate_limited(key, message)
      now = monotonic_now
      mutex.synchronize do
        @last_warn_at ||= {}
        last = @last_warn_at[key]
        return if last && (now - last) < WARN_INTERVAL_SECONDS

        @last_warn_at[key] = now
      end
      log_warn(message)
    end
    private_class_method :log_warn_rate_limited

    def log_warn(message)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("[RecordingStudioMcp::PostgresBus] #{message}")
    end
    private_class_method :log_warn
  end
end
