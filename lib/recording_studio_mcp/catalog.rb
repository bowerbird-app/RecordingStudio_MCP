# frozen_string_literal: true

require_relative "catalog/public_names"
require_relative "catalog/visibility"
require_relative "catalog/describe_tools"
require_relative "catalog/describe_shape"
require_relative "catalog/reader"

module RecordingStudioMcp
  class Catalog
    include PublicNames
    include Visibility
    include DescribeTools
    include DescribeShape
    include Reader

    def self.for(access_grant)
      api = api_from(access_grant)
      new(
        api: api,
        access_grant: access_grant,
        server: RecordingStudioMcp.configuration.catalogs.server_for(api: api)
      )
    end

    def self.api_from(access_grant)
      return "public" unless access_grant.respond_to?(:api_client)

      access_grant.api_client&.api_key.presence || "public"
    end

    def initialize(api:, access_grant: nil, server: nil)
      @api = RecordingStudioApi.configuration.fetch_api(api).name
      @access_grant = access_grant
      @server = server
    end

    attr_reader :api, :access_grant, :server

    def type_names
      @type_names ||= included_type_names.sort.freeze
    end

    def union_output_keys
      type_names.flat_map { |type| Array(registration_for(type)&.output_keys).map(&:to_s) }.uniq.sort
    end

    def type_schema
      {
        type: "string",
        enum: displayed_names_for(type_names),
        description: "Type registered on this named API. Call describe for included tools and relationships."
      }
    end

    def type_schema_for(operation)
      type_schema.merge(
        enum: displayed_names_for(type_names_for(operation)),
        description: "Type on this named API that allows #{operation}. Call describe for included tools."
      )
    end

    def displayed_names_for(types)
      types.map { |type| displayed_type_name(type) }.sort
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

    def resolved_server
      return if @server == false
      return @server if @server.is_a?(BuiltServer)

      RecordingStudioMcp.configuration.catalogs.server_for(api: api)
    end

    def capability_actions_advertised?
      resolved_server&.tool?("capability_action")
    end

    private

    def reject_nils(hash, keep: [])
      hash.reject { |key, value| value.nil? && !keep.include?(key) }
    end

    def included_type_names
      return api_registered_types if @server == false

      names = resolved_server&.type_names
      names ? names.map(&:to_s) : []
    end

    def registered_types
      included_type_names
    end

    def api_registered_types
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
