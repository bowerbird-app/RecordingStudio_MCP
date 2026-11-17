# frozen_string_literal: true

require "base64"
require "json"

module RecordingStudioMcp
  module ResourceCursor
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    MAX_BYTES = 256
    INVALID = :invalid

    module_function

    def encode(id)
      Base64.strict_encode64(JSON.generate("id" => id.to_s.downcase))
    end

    def decode(cursor)
      return if cursor.nil?
      return INVALID unless usable?(cursor)

      id_from(JSON.parse(strict_decode(cursor)))
    rescue ArgumentError, JSON::ParserError
      INVALID
    end

    def usable?(cursor)
      return false unless cursor.is_a?(String)
      return false if cursor.bytesize > MAX_BYTES
      return false unless (cursor.length % 4).zero?

      cursor.match?(%r{\A[A-Za-z0-9+/]+={0,2}\z})
    end

    def strict_decode(cursor)
      text = Base64.strict_decode64(cursor).force_encoding(Encoding::UTF_8)
      raise ArgumentError unless text.valid_encoding?

      text
    end

    def id_from(payload)
      return INVALID unless payload.is_a?(Hash) && payload.keys == ["id"]

      id = payload["id"]
      return INVALID unless id.is_a?(String) && id.match?(UUID)

      id.downcase
    end

    private_class_method :usable?, :strict_decode, :id_from
  end
end
