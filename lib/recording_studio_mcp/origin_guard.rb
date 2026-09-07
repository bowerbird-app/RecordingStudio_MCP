# frozen_string_literal: true

module RecordingStudioMcp
  class OriginGuard
    def self.allowed?(origin, request_origin:, allowed_origins:)
      return true if origin.blank?

      origins = [request_origin, *Array(allowed_origins)].compact.map { |entry| entry.to_s.delete_suffix("/") }
      origins.include?(origin.to_s.delete_suffix("/"))
    end
  end
end
