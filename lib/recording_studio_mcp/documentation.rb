# frozen_string_literal: true

require_relative "documentation/overview"
require_relative "documentation/openapi"

module RecordingStudioMcp
  module Documentation
    Page = Data.define(
      :api_key,
      :title,
      :instructions,
      :overview,
      :tools,
      :type_schema,
      :types,
      :resource_template,
      :tag_groups
    )

    module_function

    def page(api:)
      api_key = NamedApi.normalize(api)
      raise ArgumentError, "unknown API #{api_key}" unless NamedApi.known?(api_key)

      build_page(Catalog.new(api: api_key))
    end

    def openapi(api:)
      Openapi.document(page(api: api))
    end

    def build_page(catalog)
      surface = ToolSurface.for(api: catalog.api)
      types = describe_types(catalog)
      Page.new(**page_fields(catalog, surface, types))
    end

    def page_fields(catalog, surface, types)
      {
        api_key: catalog.api, title: title_for(catalog.api),
        instructions: Instructions.text(access_grant: nil, api: catalog.api, surface: surface).to_s,
        overview: Overview.markdown(surface), tools: Array(surface.tool_definitions),
        type_schema: catalog.type_schema || empty_type_schema, types: types,
        resource_template: resource_template, tag_groups: ToolDocs.tag_groups(surface, types: types)
      }
    end

    def resource_template
      {
        name: Resources::TEMPLATE_NAME,
        uriTemplate: Resources::URI_TEMPLATE,
        mimeType: Resources::MIME_TYPE
      }
    end

    def title_for(api_key)
      key = NamedApi.normalize(api_key)
      key == NamedApi::DEFAULT ? "Public MCP" : "#{key.humanize} MCP"
    end

    def describe_types(catalog)
      Array(catalog.type_names).filter_map { |type_name| describe_type(catalog, type_name) }
    end

    def describe_type(catalog, type_name)
      catalog.describe(type_name)
    rescue RecordingStudioApi::InvalidActionInputError, RecordingStudioApi::NotFoundError
      empty_type_describe(type_name)
    end

    def empty_type_describe(type_name)
      {
        "type" => type_name.to_s,
        "operations" => [],
        "writable_fields" => [],
        "capability_actions" => []
      }
    end

    def empty_type_schema
      {
        type: "string",
        enum: [],
        description: "Type registered on this named API. Call describe for writable fields and actions."
      }
    end

    private_class_method :build_page, :page_fields, :title_for, :describe_types, :describe_type,
                         :empty_type_describe, :empty_type_schema, :resource_template
  end
end
