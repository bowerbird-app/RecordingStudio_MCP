# frozen_string_literal: true

require_relative "catalogs/builder"
require_relative "catalogs/audit"

module RecordingStudioMcp
  class Catalogs
    GENERIC_NAMES = GenericTools.names.freeze
    DESCRIBE_NAME = "describe"
    READ_SKILL_NAME = "read_skill"
    OPERATION_TOOLS = {
      "list" => :index,
      "show" => :show,
      "create" => :create,
      "update" => :update,
      "delete" => :destroy
    }.freeze

    def initialize(configuration)
      @configuration = configuration
      @by_api = nil
      @by_name = nil
    end

    def server_for(api:)
      build_if_needed
      @by_api[NamedApi.normalize(api)]
    end

    def server_named(name)
      build_if_needed
      @by_name[name.to_s]
    end

    def servers
      build_if_needed
      @by_name.values
    end

    def invalidate!
      @by_api = nil
      @by_name = nil
    end

    def build!
      @by_api, @by_name = Builder.new(@configuration).call
      self
    end

    def audit_lines
      servers.flat_map { |server| Audit.lines(server) }
    end

    def audit!
      build!
      mismatches = servers.flat_map { |server| Audit.mismatches(server) }
      raise RecordingStudioApi::ConfigurationError, mismatches.join("\n") if mismatches.any?

      audit_lines
    end

    private

    def build_if_needed
      build! if @by_name.nil?
    end
  end
end
