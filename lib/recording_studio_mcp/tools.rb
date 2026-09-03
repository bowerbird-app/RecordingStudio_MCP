# frozen_string_literal: true

module RecordingStudioMcp
  module Tools
    NAMES = %w[list show create update capability_action describe].freeze

    module_function

    def definitions(access_grant: nil, api: nil)
      Catalog.new(api: api || Catalog.api_from(access_grant)).tool_definitions
    end

    def known?(name)
      NAMES.include?(name.to_s)
    end
  end
end
