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
    # Public Rails signals only: Console, Rake top-level tasks, runner ARGV,
    # plus START_ENV.
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

        register_shutdown_hook!
        @running = true
        @thread = Thread.new { listen_loop }
      end
    end

    # Signal the LISTEN loop to exit, wake it, join the thread, then release the
    # dedicated connection. Safe to call more than once.
    def stop!
      thread = nil
      mutex.synchronize do
        @running = false
        thread = @thread
        @thread = nil
      end

      wake_listen_loop
      thread&.join(STOP_JOIN_TIMEOUT)
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

    def rails_runner?
      program = File.basename($PROGRAM_NAME.to_s)
      %w[rails rake].include?(program) && ARGV.first.to_s == "runner"
    end
    private_class_method :rails_runner?

    def register_shutdown_hook!
      return if @shutdown_hook_registered

      @shutdown_hook_registered = true
      # at_exit runs LIFO: register after ActiveRecord so we stop before it
      # disconnects the pool on process exit.
      at_exit { stop! }
    end
    private_class_method :register_shutdown_hook!

    def listen_loop
      raw = open_listen_socket
      poll_notifications(raw)
    ensure
      release_listen_connection
    end
    private_class_method :listen_loop

    def open_listen_socket
      connection = listen_connection
      connection.execute("LISTEN #{CHANNEL}")
      connection.raw_connection
    end
    private_class_method :open_listen_socket

    def poll_notifications(raw)
      wait_once(raw) while running?
    end
    private_class_method :poll_notifications

    def wait_once(raw)
      raw.wait_for_notify(WAIT_TIMEOUT_SECONDS) do |_channel, _pid, payload|
        handle_payload(payload)
      end
    rescue StandardError => e
      # Stream closed during shutdown or pool teardown — exit quietly.
      raise unless listen_notify_error?(e)

      mutex.synchronize { @running = false }
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

    def listen_notify_error?(error)
      return true if error.is_a?(IOError)
      return true if defined?(PG::Error) && error.is_a?(PG::Error)

      false
    end
    private_class_method :listen_notify_error?
  end
end
