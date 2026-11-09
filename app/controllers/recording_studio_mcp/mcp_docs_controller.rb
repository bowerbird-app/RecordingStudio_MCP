# frozen_string_literal: true

module RecordingStudioMcp
  class McpDocsController < ApplicationController
    helper RecordingStudioMcp::McpDocsHelper
    recording_studio_layout { documentation_layout }

    before_action :load_api_key
    before_action :ensure_documentation_enabled
    before_action :authorize_documentation
    before_action :load_documentation_page

    def show
      @api_title = @page.title
    end

    private

    def load_api_key
      @api_key = NamedApi.normalize(params[:api_key])
      head :not_found unless NamedApi.known?(@api_key)
    end

    def ensure_documentation_enabled
      return if performed?

      head :not_found unless RecordingStudioMcp.configuration.documentation_enabled
    end

    def authorize_documentation
      return if performed? || public_documentation?

      actor = documentation_actor
      deny_documentation(actor) unless documentation_allowed?(actor)
    end

    def public_documentation?
      RecordingStudioMcp.configuration.documentation_access == :public
    end

    def documentation_allowed?(actor)
      access = RecordingStudioMcp.configuration.documentation_access
      return actor.present? if access == :authenticated
      return false unless access.respond_to?(:call)

      access.call(controller: self, actor: actor, api: @api_key)
    end

    def deny_documentation(actor)
      head(actor.present? ? :forbidden : :unauthorized)
    end

    def load_documentation_page
      return if performed?

      oauth_client = documentation_oauth_client
      if oauth_client && oauth_client_api_mismatch?(oauth_client)
        head :not_found
        return
      end

      @page = Documentation.page(api: @api_key, oauth_client: oauth_client)
    rescue ArgumentError, KeyError, RecordingStudioApi::ConfigurationError
      head :not_found
    end

    def documentation_oauth_client
      id = params[:oauth_client_id]
      return if id.blank?
      return unless defined?(RecordingStudioOauth::OauthClient)

      RecordingStudioOauth::OauthClient.find_by(id: id)
    end

    def oauth_client_api_mismatch?(oauth_client)
      client_api = Documentation.oauth_client_api_key(oauth_client)
      client_api.present? && client_api != @api_key
    end

    def documentation_actor
      return send(:current_user) if respond_to?(:current_user, true) && send(:current_user).present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def documentation_layout
      layout_name = RecordingStudioMcp.configuration.documentation_layout_name
      layout_name.present? ? layout_name : "recording_studio/default_layout"
    end
  end
end
