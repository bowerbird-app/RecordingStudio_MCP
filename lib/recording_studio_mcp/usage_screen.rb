# frozen_string_literal: true

require "recording_studio_admin"

module RecordingStudioMcp
  module Admin
    class UsageScreen < RecordingStudioAdmin::Screen
      # A second load reopens this class. filter appends, so clear the list first.
      @filters_value = []
      @widget_usages_value = []

      key "mcp_usage"
      title "Usage"
      subtitle "Every call from the last 4 weeks."
      blast_radius :site

      query { |_context| RecordingStudioMcp::UsageWindow.logs }
      filter :date_range, field: :occurred_at, default: :last_4_weeks
      filter :group_by, values: %i[day week], default: :day

      summary do
        label "Calls"
        hide_change
      end

      chart do
        title "Calls"
        type :column
        series do |context|
          [{
            name: "Calls",
            data: RecordingStudioAdmin::AdminActivityLogsSupport.date_series(
              context.query_result.relation,
              field: :occurred_at,
              bucket: context.filter_value(:group_by) || :day
            )
          }]
        end
      end

      table do
        title "Recent calls"
        column :occurred_at, title: "When"
        column :method_name, title: "Method"
        column :subject_name, title: "Name"
        column :status_code, title: "Status"
        column :failed, title: "Failed", value: ->(row, _context) { row.failed ? "Yes" : "No" }
        column :duration_ms, title: "Duration", value: ->(row, _context) { "#{row.duration_ms} ms" }
        default_sort :occurred_at, direction: :desc
        paginate per_page: 25
      end
    end
  end
end
