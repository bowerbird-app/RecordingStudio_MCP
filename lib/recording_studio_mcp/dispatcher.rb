# frozen_string_literal: true

require "action_controller"

module RecordingStudioMcp
  class Dispatcher
    RESOURCE_TOOLS = {
      "list" => :index,
      "show" => :show,
      "create" => :create,
      "update" => :update,
      "delete" => :destroy
    }.freeze
    WRITE_RESERVED_KEYS = %w[type parent_id id idempotency_key].freeze
    SUCCESS_STATUS_RANGE = (200..299)

    def self.call(tool_name:, arguments:, access_grant:, idempotency_key: nil, request_context: nil)
      new(
        access_grant: access_grant,
        idempotency_key: idempotency_key,
        request_context: request_context
      ).call(tool_name, arguments)
    end

    def initialize(access_grant:, idempotency_key: nil, request_context: nil)
      @access_grant = access_grant
      @idempotency_key = idempotency_key
      @request_context = request_context
      @surface = ToolSurface.for(access_grant: access_grant)
      @catalog = @surface.catalog
    end

    def call(tool_name, arguments)
      AuthorizedBy.enter(access_grant)
      dispatch_named(tool_name, arguments)
    rescue RecordingStudioApi::AuthorizationError,
           RecordingStudioApi::NotFoundError,
           RecordingStudioApi::UnsupportedActionError,
           RecordingStudioApi::InvalidActionInputError,
           RecordingStudioApi::InvalidPaginationTokenError => e
      error_result(e.message)
    ensure
      AuthorizedBy.leave
    end

    private

    attr_reader :access_grant, :idempotency_key, :request_context, :catalog, :surface

    def dispatch_named(tool_name, arguments)
      return error_result("arguments must be an object") unless argument_object?(arguments)

      name = tool_name.to_s
      return error_result(unknown_tool_message(name)) unless surface.known?(name)

      dispatch_known(name, arguments)
    end

    def dispatch_known(name, arguments)
      metric = surface.metric_tool(name)
      if metric
        return wrap_metric(
          MetricTools.execute(metric, arguments, access_grant, progress_reporter: progress_reporter)
        )
      end

      args = stringify_keys(arguments)
      return dispatch_tree(name, args) if surface.tree_tool?(name)

      dispatch_endpoint(surface.endpoint_for(name), args)
    end

    def wrap_metric(result)
      return render_handler_result(result) if result.is_a?(Hash) && result.key?(:json)

      success_result(result)
    end
  end
end

require "recording_studio_mcp/dispatcher/tree"
require "recording_studio_mcp/dispatcher/endpoint"
require "recording_studio_mcp/dispatcher/contexts"
require "recording_studio_mcp/dispatcher/recordings"
require "recording_studio_mcp/dispatcher/results"
