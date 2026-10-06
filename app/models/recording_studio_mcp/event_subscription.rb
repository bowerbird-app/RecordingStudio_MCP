# frozen_string_literal: true

module RecordingStudioMcp
  class EventSubscription < ApplicationRecord
    self.table_name = "recording_studio_mcp_event_subscriptions"
    self.primary_key = "id"

    ACTIVE = "active"
    INACTIVE = "inactive"
    FAILURE_LIMIT = 5

    encrypts :callback_secret

    scope :active, -> { where(status: ACTIVE).where("expires_at > ?", Time.current) }

    def self.table_available?
      connection_pool.with_connection { |connection| connection.data_source_exists?(table_name) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      false
    end

    def active?
      status == ACTIVE && expires_at.present? && expires_at > Time.current
    end

    def matches_recording?(recording)
      wanted = arguments.stringify_keys["recording_id"].to_s
      return false if wanted.blank?

      wanted == recording.id.to_s
    end

    def mark_delivered!
      update!(last_delivered_at: Time.current, last_error: nil, failure_count: 0, status: ACTIVE)
    end

    def record_failure!(message:, inactive: false)
      count = failure_count.to_i + 1
      attrs = { last_error: message.to_s.truncate(255), failure_count: count }
      attrs[:status] = INACTIVE if inactive || count >= FAILURE_LIMIT
      update!(attrs)
    end

    def deactivate!(message:)
      update!(status: INACTIVE, last_error: message.to_s.truncate(255))
    end

    def refresh!(secret:, expires_at:, access_recording_id: nil)
      attrs = {
        callback_secret: secret,
        expires_at: expires_at,
        status: ACTIVE,
        last_error: nil,
        failure_count: 0
      }
      attrs[:access_recording_id] = access_recording_id if access_recording_id.present?
      update!(attrs)
    end
  end
end
