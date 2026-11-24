# frozen_string_literal: true

module RecordingStudioMcp
  module FileParams
    module_function

    def redact(value, source)
      secrets = secret_urls(source)
      return value if secrets.empty?

      scrub(value, secrets)
    end

    def secret_urls(source)
      found = []
      collect_secrets(source, found)
      found.uniq.sort_by { |secret| -secret.length }
    end

    def collect_secrets(value, found)
      case value
      when Hash
        value.each do |key, entry|
          found << entry if key.to_s == "download_url" && url?(entry)
          collect_secrets(entry, found)
        end
      when Array
        value.each { |entry| collect_secrets(entry, found) }
      end
    end

    def url?(value)
      value.is_a?(String) && value.include?("://")
    end

    def scrub(value, secrets)
      case value
      when String
        secrets.reduce(value) { |text, secret| text.gsub(secret, REDACTED) }
      when Hash
        value.transform_values { |entry| scrub(entry, secrets) }
      when Array
        value.map { |entry| scrub(entry, secrets) }
      else
        value
      end
    end
    private_class_method :secret_urls, :collect_secrets, :url?, :scrub
  end
end
