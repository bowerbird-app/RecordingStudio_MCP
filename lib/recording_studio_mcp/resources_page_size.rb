# frozen_string_literal: true

module RecordingStudioMcp
  module ResourcesPageSize
    module_function

    def parse(value)
      raise ArgumentError, "resources_page_size must be a positive integer" unless positive?(value)

      Integer(value)
    end

    def positive?(value)
      return value.positive? if value.is_a?(Integer)

      value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)
    end
    private_class_method :positive?
  end
end
