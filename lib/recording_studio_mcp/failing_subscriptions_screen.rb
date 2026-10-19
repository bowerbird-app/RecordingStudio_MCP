# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
    class FailingSubscriptionsScreen < RecordingStudioAdmin::Screen
      @filters_value = []
      @widget_usages_value = []

      key "mcp_failing_subscriptions"
      title "Failing subscriptions"
      subtitle "Still listening, but the last callback bounced."
      blast_radius :site

      query { |_context| RecordingStudioMcp::EventSubscription.failing }

      table do
        title "Open callbacks that missed"
        column :event_name, title: "Event"
        column :callback_url, title: "Callback"
        column :failure_count, title: "Misses"
        column :last_error, title: "Last error"
        column :expires_at, title: "Expires"
        column :last_delivered_at, title: "Last delivered"
        default_sort :failure_count, direction: :desc
        paginate per_page: 25
      end
    end
  end
end
