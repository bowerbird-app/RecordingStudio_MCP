# frozen_string_literal: true

module RecordingStudioMcp
  class UsageDayMetricRollup < ApplicationRecord
    self.table_name = "recording_studio_mcp_usage_day_metric_rollups"
    self.primary_key = nil

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end
  end
end
