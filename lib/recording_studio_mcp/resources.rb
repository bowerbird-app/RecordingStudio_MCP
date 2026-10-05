# frozen_string_literal: true

module RecordingStudioMcp
  module Resources
    SCHEME = "recording://"
    MIME_TYPE = "application/json"
    RESOURCE_NOT_FOUND = -32_002

    List = Data.define(:payload)
    Read = Data.define(:payload)
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

    def list(access_grant:, cursor: nil)
      return InvalidParams.new unless cursor.nil?

      List.new(payload: complete(resources: listed_resources(access_grant)))
    end

    def read(access_grant:, uri:)
      recording_id = recording_id_from(uri)
      return InvalidParams.new if recording_id.nil?

      recording = find_accessible(access_grant, recording_id)
      return NotFound.new(uri: uri) if recording.nil?

      Read.new(payload: complete(contents: [content_for(recording)]))
    end

    def find_accessible(access_grant, recording_id)
      scope = accessible_scope(access_grant)
      return if scope.nil?

      scope.find_by(id: recording_id)
    end

    def accessible?(access_grant, uri)
      recording_id = recording_id_from(uri)
      return false if recording_id.nil?

      find_accessible(access_grant, recording_id).present?
    end

    def listed_resources(access_grant)
      skill_resources(access_grant) + recording_resources(access_grant)
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

    def complete(extra)
      { resultType: "complete" }.merge(extra).merge(ttlMs: 0, cacheScope: "private")
    end
    private_class_method :complete, :listed_resources, :skill_resources, :recording_resources,
                         :recordings_for, :content_for
  end
end
