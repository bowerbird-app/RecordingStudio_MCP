# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    Page = Data.define(
      :api_key,
      :title,
      :instructions,
      :tools,
      :type_schema,
      :types,
      :resource_template
    )

    module_function

    def page(api:, access_grant: nil, oauth_client: nil)
      api_key = resolve_api_key(api: api, access_grant: access_grant, oauth_client: oauth_client)
      raise ArgumentError, "unknown API #{api_key}" unless NamedApi.known?(api_key)

      catalog = catalog_for(api_key: api_key, access_grant: access_grant)
      build_page(catalog, access_grant)
    end

    def build_page(catalog, access_grant)
      Page.new(
        api_key: catalog.api,
        title: title_for(catalog.api),
        instructions: Instructions.text(access_grant: access_grant).to_s,
        tools: Array(Tools.definitions(access_grant: access_grant, api: catalog.api)),
        type_schema: catalog.type_schema || empty_type_schema,
        types: describe_types(catalog),
        resource_template: resource_template
      )
    end

    def resource_template
      {
        name: Resources::TEMPLATE_NAME,
        uriTemplate: Resources::URI_TEMPLATE,
        mimeType: Resources::MIME_TYPE
      }
    end

    def resolve_api_key(api:, access_grant:, oauth_client:)
      from_client = oauth_client_api_key(oauth_client)
      return from_client if from_client.present?
      return Catalog.api_from(access_grant) if access_grant

      NamedApi.normalize(api)
    end

    def catalog_for(api_key:, access_grant:)
      return Catalog.for(access_grant) if access_grant

      Catalog.new(api: api_key)
    end

    def oauth_client_api_key(oauth_client)
      return if oauth_client.nil?

      key = if oauth_client.respond_to?(:api_key)
              oauth_client.api_key
            elsif oauth_client.respond_to?(:api)
              oauth_client.api
            end
      NamedApi.normalize(key) if key.present?
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
    rescue StandardError
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

    private_class_method :resolve_api_key, :catalog_for, :build_page, :title_for, :describe_types,
                         :describe_type, :empty_type_schema, :resource_template
  end
end
