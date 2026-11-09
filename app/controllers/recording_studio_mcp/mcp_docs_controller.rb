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

      @page = Documentation.page(api: @api_key)
    rescue ArgumentError, KeyError, RecordingStudioApi::ConfigurationError
      head :not_found
    end

    def documentation_actor
      user = current_user if respond_to?(:current_user)
      return user if user.present?
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)

      nil
    end

    def documentation_layout
      layout_name = RecordingStudioMcp.configuration.documentation_layout_name
      return layout_name if layout_name.present?

      RecordingStudio.configuration.resolved_layout(controller: self)
    end
  end
end
