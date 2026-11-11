# frozen_string_literal: true

require_relative "catalog/visibility"
require_relative "catalog/describe_shape"
require_relative "catalog/reader"

module RecordingStudioMcp
  class Catalog
    include Visibility
    include DescribeShape
    include Reader

    def self.for(access_grant)
      new(api: api_from(access_grant), access_grant: access_grant)
    end

    def self.api_from(access_grant)
      access_grant&.api_client&.api_key.presence || "public"
    end

    def initialize(api:, access_grant: nil)
      @api = RecordingStudioApi.configuration.fetch_api(api).name
      @access_grant = access_grant
    end

    attr_reader :api, :access_grant

    def type_names
      @type_names ||= registered_types.sort.freeze
    end

    def union_output_keys
      type_names.flat_map { |type| Array(registration_for(type)&.output_keys).map(&:to_s) }.uniq.sort
    end

    def type_schema
      {
        type: "string",
        enum: type_names,
        description: "Type registered on this named API. Call describe for writable fields and actions."
      }
    end

    def type_schema_for(operation)
      type_schema.merge(
        enum: type_names_for(operation),
        description: "Type on this named API that allows #{operation}. Call describe for operations."
      )
    end

    def registered_endpoints
      RecordingStudioApi.configuration.fetch_api(api).registered_endpoint_registry.all
    end

    def list_parent_id?
      list_parent_id_type_names.any?
    end

    def list_parent_id_type_names
      configured = configured_parent_id_list_types
      return [] if configured.empty?

      type_names_for(:index).select { |type| configured.include?(type) }
    end

    private

    def registered_types
      registry = RecordingStudioApi.configuration.fetch_api(api).recordable_registry
      registry.to_h.keys.map(&:to_s)
    end

    def registration_for(type)
      RecordingStudioApi.recordable_registration_for(type, api: api)
    end

    def configured_parent_id_list_types
      Array(RecordingStudioMcp.configuration.list_parent_id_types).map(&:to_s)
    end
  end
end
