# frozen_string_literal: true

module RecordingStudioMcp
  class UsageLog < ApplicationRecord
    self.table_name = "recording_studio_mcp_usage_logs"

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.record_payload!(payload)
      return unless table_available?

      create!(payload.merge(occurred_at: Time.current))
    end
  end
end
