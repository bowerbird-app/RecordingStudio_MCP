# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module_function

    def page_fields(catalog)
      surface = ToolSurface.for(api: catalog.api)
      types = describe_types(catalog)
      catalog_page_fields(catalog, surface, types).merge(docs_page_fields(surface, types))
    end

    def catalog_page_fields(catalog, surface, types)
      {
        api_key: catalog.api,
        title: title_for(catalog.api),
        instructions: Instructions.text(access_grant: nil, api: catalog.api, surface: surface).to_s,
        tools: ToolDocs.docs_tools(surface),
        type_schema: catalog.type_schema || empty_type_schema,
        types: types,
        resource_template: resource_template
      }
    end
    private_class_method :catalog_page_fields

    def docs_page_fields(surface, types)
      {
        overview: Overview.markdown(surface),
        tag_groups: ToolDocs.tag_groups(surface, types: types)
      }
    end
    private_class_method :docs_page_fields
  end
end
