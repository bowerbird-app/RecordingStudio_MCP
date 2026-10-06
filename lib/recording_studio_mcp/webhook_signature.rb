# frozen_string_literal: true

require "base64"
require "openssl"

module RecordingStudioMcp
  module WebhookSignature
    VERSION = "v1"

    module_function

    def header(id:, timestamp:, body:, secret:)
      "#{VERSION},#{digest(id: id, timestamp: timestamp, body: body, secret: secret)}"
    end

    def digest(id:, timestamp:, body:, secret:)
      key = WebhookSecret.parse(secret) || WebhookSecret.parse("#{WebhookSecret::PREFIX}#{secret}")
      raise ArgumentError, "invalid signing secret" if key.nil?

      signed = "#{id}.#{timestamp}.#{body}"
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, signed))
    end

    def valid?(id:, timestamp:, body:, secret:, header:)
      expected = header(id: id, timestamp: timestamp, body: body, secret: secret)
      return false unless header.is_a?(String)

      header.split.any? do |entry|
        next false unless entry.start_with?("#{VERSION},")

        ActiveSupport::SecurityUtils.secure_compare(entry, expected)
      end
    rescue ArgumentError, TypeError
      false
    end
  end
end
