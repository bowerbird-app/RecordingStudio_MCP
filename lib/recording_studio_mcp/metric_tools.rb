# frozen_string_literal: true

require "action_controller"

module RecordingStudioMcp
  module MetricTools
    TOOL_NAME_PATTERN = /\A[a-z][a-z0-9_]*-[a-z][a-z0-9_]*\z/
    FILTER_PARAMETER = /\Afilter\[(.+)\]\z/
    BRACKET_FILTER_KEY = /\Afilter\[.+\]\z/
    FILTER_DESCRIPTION = "Exact-match list filters. Keys are attribute names. The API reads this as params[:filter]."

    module_function

    def warn_skipped(name, reason = nil)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      detail = reason.present? ? "#{name}: #{reason}" : name.to_s
      Rails.logger.warn("[RecordingStudioMcp] skipped metric #{detail}")
    end

    def params_for(tool, arguments)
      tool.catalog? ? catalog_params_for(tool, arguments) : recordable_params_for(tool, arguments)
    end

    def execute(tool, arguments, access_grant, progress_reporter: nil)
      if tool.catalog?
        execute_catalog(tool, arguments, access_grant, progress_reporter: progress_reporter)
      else
        execute_recordable(tool, arguments, access_grant)
      end
    end
  end
end

require "recording_studio_mcp/metric_tools/tool"
require "recording_studio_mcp/metric_tools/argument_plan"
require "recording_studio_mcp/metric_tools/recordable/registered_entry"
require "recording_studio_mcp/metric_tools/recordable/listing"
require "recording_studio_mcp/metric_tools/recordable/arguments"
require "recording_studio_mcp/metric_tools/recordable/execution"
require "recording_studio_mcp/metric_tools/catalog"
