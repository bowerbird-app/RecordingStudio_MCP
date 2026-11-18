# frozen_string_literal: true

require "recording_studio_mcp/resource_cursor"
require "recording_studio_mcp/resource_page"

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
      after_id = ResourceCursor.decode(cursor)
      return InvalidParams.new if after_id == ResourceCursor::INVALID

      page = ResourcePage.new(accessible_scope(access_grant), after_id: after_id, page_size: page_size)
      List.new(payload: complete(list_payload(access_grant, page, after_id.nil?), protocol_version))
    end

    def read(access_grant:, uri:, protocol_version: nil)
      return UiResources.read(access_grant: access_grant, uri: uri, protocol_version: protocol_version) if ui_uri?(uri)

      recording_id = recording_id_from(uri)
      return InvalidParams.new if recording_id.nil?

      recording = find_accessible(access_grant, recording_id)
      return NotFound.new(uri: uri) if recording.nil?

      Read.new(payload: complete({ contents: [content_for(recording, access_grant)] }, protocol_version))
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
      return UiResources.accessible?(access_grant, uri) if ui_uri?(uri)

      recording_id = recording_id_from(uri)
      return false if recording_id.nil?

      find_accessible(access_grant, recording_id).present?
    end

    def listed_resources(access_grant, recordings, first_page:)
      cards = recording_cards(recordings, access_grant)
      return cards unless first_page

      skill_resources(access_grant) + cards + UiResources.listed(access_grant)
    end

    def ui_uri?(uri)
      McpUi.widget_id_from_uri(uri).present?
    end

    def complete(extra, protocol_version)
      ResultShape.complete(extra, protocol_version: protocol_version)
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

    def list_payload(access_grant, page, first_page)
      payload = { resources: listed_resources(access_grant, page.recordings, first_page: first_page) }
      return payload unless page.more?

      payload.merge(nextCursor: ResourceCursor.encode(page.recordings.last.id))
    end

    def page_size
      RecordingStudioMcp.configuration.resources_page_size
    end

    def recording_cards(recordings, access_grant)
      catalog = catalog_for(access_grant)
      recordings.map { |recording| RecordingCard.new(recording, catalog: catalog).list_entry }
    end

    def accessible_scope(access_grant)
      return unless access_grant.respond_to?(:accessible_recordings)

      access_grant.accessible_recordings
    end

    def content_for(recording, access_grant)
      RecordingCard.new(recording, catalog: catalog_for(access_grant)).content
    end

    def catalog_for(access_grant)
      Catalog.for(access_grant)
    end

    def recording_template
      { name: TEMPLATE_NAME, uriTemplate: URI_TEMPLATE, mimeType: MIME_TYPE }
    end

    private_class_method :complete, :listed_resources, :list_payload, :page_size, :skill_resources,
                         :recording_cards, :content_for, :catalog_for, :recording_template, :ui_uri?
  end
end
