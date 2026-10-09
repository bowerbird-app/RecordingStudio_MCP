# frozen_string_literal: true

module RecordingStudioMcp
  module Resources
    SCHEME = "recording://"
    MIME_TYPE = "application/json"
    RESOURCE_NOT_FOUND = -32_002
    URI_TEMPLATE = "recording://{id}"
    TEMPLATE_NAME = "Recording"

    List = Data.define(:payload)
    Read = Data.define(:payload)
    Templates = Data.define(:payload)
    InvalidParams = Class.new
    NotFound = Data.define(:uri)

    module_function

    def uri_for(recording)
      "#{SCHEME}#{recording.id}"
    end

    def recording_id_from(uri)
      return nil unless uri.is_a?(String)
      return nil unless uri.start_with?(SCHEME)

      id = uri.delete_prefix(SCHEME)
      return nil if id.blank? || id.include?("/")

      id
    end

    def list(access_grant:, cursor: nil, protocol_version: nil)
      return InvalidParams.new unless cursor.nil?

      List.new(payload: complete({ resources: listed_resources(access_grant) }, protocol_version))
    end

    def read(access_grant:, uri:, protocol_version: nil)
      return read_ui(access_grant: access_grant, uri: uri, protocol_version: protocol_version) if ui_uri?(uri)

      recording_id = recording_id_from(uri)
      return InvalidParams.new if recording_id.nil?

      recording = find_accessible(access_grant, recording_id)
      return NotFound.new(uri: uri) if recording.nil?

      Read.new(payload: complete({ contents: [content_for(recording)] }, protocol_version))
    end

    def templates(cursor: nil, protocol_version: nil)
      return InvalidParams.new unless cursor.nil?

      Templates.new(payload: complete({ resourceTemplates: [recording_template] }, protocol_version))
    end

    def find_accessible(access_grant, recording_id)
      scope = accessible_scope(access_grant)
      return if scope.nil?

      scope.find_by(id: recording_id)
    end

    def accessible?(access_grant, uri)
      return ui_accessible?(access_grant, uri) if ui_uri?(uri)

      recording_id = recording_id_from(uri)
      return false if recording_id.nil?

      find_accessible(access_grant, recording_id).present?
    end

    def listed_resources(access_grant)
      skill_resources(access_grant) + recording_resources(access_grant) + ui_resources(access_grant)
    end

    def ui_uri?(uri)
      McpUi.widget_id_from_uri(uri).present?
    end

    def read_ui(access_grant:, uri:, protocol_version:)
      widget_id = McpUi.widget_id_from_uri(uri)
      return NotFound.new(uri: uri) unless ui_accessible?(access_grant, uri)

      document = McpUi.package(widget_id, data: {})
      return NotFound.new(uri: uri) if document.nil?

      Read.new(payload: complete({ contents: [document.to_mcp_resource] }, protocol_version))
    end

    def ui_accessible?(access_grant, uri)
      widget_id = McpUi.widget_id_from_uri(uri)
      return false if widget_id.blank?

      api = Catalog.api_from(access_grant)
      version = RecordingStudioApi.default_api_version(api: api)
      McpUi.available?(widget_id, access_grant: access_grant, api: api, version: version)
    end

    def ui_resources(access_grant)
      api = Catalog.api_from(access_grant)
      version = RecordingStudioApi.default_api_version(api: api)
      McpUi.list.filter_map do |widget|
        next unless McpUi.available?(widget.id, access_grant: access_grant, api: api, version: version)

        {
          uri: widget.resource_uri,
          name: widget.id,
          mimeType: McpUi::MIME_TYPE
        }
      end
    end

    def skill_resources(access_grant)
      RecordingStudioMcp.exposed_skills(access_grant: access_grant).filter_map do |registration|
        document = Skills::Document.read(registration)
        next if document.nil?

        {
          uri: document.uri,
          name: registration.name,
          mimeType: "text/markdown"
        }
      end
    end

    def recording_resources(access_grant)
      recordings_for(access_grant).map { |recording| RecordingCard.new(recording).list_entry }
    end

    def recordings_for(access_grant)
      scope = accessible_scope(access_grant)
      return [] if scope.nil?

      relation = scope.respond_to?(:includes) ? scope.includes(:recordable) : scope
      relation.respond_to?(:order) ? relation.order(:id) : Array(relation)
    end

    def accessible_scope(access_grant)
      return unless access_grant.respond_to?(:accessible_recordings)

      access_grant.accessible_recordings
    end

    def content_for(recording)
      RecordingCard.new(recording).content
    end

    def complete(extra, protocol_version)
      ResultShape.complete(extra, protocol_version: protocol_version)
    end

    def recording_template
      { name: TEMPLATE_NAME, uriTemplate: URI_TEMPLATE, mimeType: MIME_TYPE }
    end

    private_class_method :complete, :listed_resources, :skill_resources, :recording_resources,
                         :recordings_for, :content_for, :recording_template, :ui_uri?, :read_ui,
                         :ui_accessible?, :ui_resources
  end
end
