# frozen_string_literal: true

require "json"

module RecordingStudioMcp
  module PostgresBus
    CHANNEL = "recording_studio_mcp_events"

    module_function

    def enabled?
      return false unless defined?(ActiveRecord::Base)
      return false unless ActiveRecord::Base.connected?

      ActiveRecord::Base.connection.adapter_name.match?(/postg/i)
    rescue StandardError
      false
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

      mutex.synchronize do
        return if @thread&.alive?

        @running = true
        @thread = Thread.new { listen_loop }
      end
    end

    def stop!
      mutex.synchronize { @running = false }
      @thread&.join(2)
      @thread = nil
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

    def listen_loop
      connection = listen_connection
      connection.execute("LISTEN #{CHANNEL}")
      raw = connection.raw_connection
      while running?
        raw.wait_for_notify(1) do |_channel, _pid, payload|
          handle_payload(payload)
        end
      end
    ensure
      release_listen_connection
    end
    private_class_method :listen_loop

    def running?
      mutex.synchronize { @running == true }
    end
    private_class_method :running?

    def listen_connection
      @listen_connection ||= ActiveRecord::Base.connection_pool.checkout
    end
    private_class_method :listen_connection

    def release_listen_connection
      connection = @listen_connection
      @listen_connection = nil
      return if connection.nil?

      connection.execute("UNLISTEN #{CHANNEL}")
      ActiveRecord::Base.connection_pool.checkin(connection)
    rescue StandardError
      nil
    end
    private_class_method :release_listen_connection
  end
end
