# frozen_string_literal: true

module RecordingStudioMcp
  class UsageLog < ApplicationRecord
    self.table_name = "recording_studio_mcp_usage_logs"

    before_validation :assign_count_flags

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.record_payload!(payload)
      return unless table_available?

      create!(payload.merge(occurred_at: Time.current))
    end

    private

    def assign_count_flags
      self.failed_count = failed ? 1 : 0 if has_attribute?(:failed_count)
      self.rate_limited_count = rate_limited ? 1 : 0 if has_attribute?(:rate_limited_count)
    end
  end
end
