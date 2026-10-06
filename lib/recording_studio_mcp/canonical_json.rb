# frozen_string_literal: true

module RecordingStudioMcp
  module CanonicalJson
    module_function

    def dump(value)
      serialize(normalize(value))
    end

    def normalize(value)
      case value
      when Hash
        value.to_h { |key, entry| [key.to_s, normalize(entry)] }.sort.to_h
      when Array
        value.map { |entry| normalize(entry) }
      else
        value
      end
    end

    def serialize(value)
      JSON.generate(value)
    end
    private_class_method :serialize
  end
end
