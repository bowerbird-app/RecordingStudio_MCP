# frozen_string_literal: true

require "base64"

module RecordingStudioMcp
  module WebhookSecret
    PREFIX = "whsec_"
    KEY_BYTES = (24..64)

    module_function

    def parse(secret)
      return nil unless secret.is_a?(String)
      return nil unless secret.start_with?(PREFIX)

      encoded = secret.delete_prefix(PREFIX)
      return nil if encoded.blank?

      decoded = Base64.strict_decode64(encoded)
      return nil unless KEY_BYTES.cover?(decoded.bytesize)

      decoded
    rescue ArgumentError
      nil
    end
  end
end
