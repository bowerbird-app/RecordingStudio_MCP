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
    FINGERPRINT_EXCLUDED_KEYS = %w[idempotency_key authorized_by_type authorized_by_id].freeze
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
    rescue *TOOL_ERROR_CLASSES => e
      tool_error_for(e)
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
      args = stringify_keys(arguments)
      metric = surface.metric_tool(name)
      return execute_metric(metric, args) if metric
      return dispatch_tree(name, args) if surface.tree_tool?(name)

      built = surface.server&.tool(name)
      return dispatch_registered(built, args) if built&.registration

      dispatch_endpoint(surface.endpoint_for(name), args)
    end

    def execute_metric(metric, args)
      wrap_metric(metric, MetricTools.execute(metric, args, access_grant, progress_reporter: progress_reporter))
    end

    def dispatch_registered(built, args)
      registration = built.registration
      return dispatch_endpoint(surface.endpoint_for(built.name), args) if registration.target.endpoint?

      dispatch_registered_target(registration, args)
    end

    def dispatch_registered_target(registration, args)
      if registration.target.operation?
        dispatch_resource(registration.target.value, args.merge(forced_registration_args(registration)))
      else
        dispatch_capability_action(
          args.merge("action" => registration.target.value.to_s),
          type_name: registration.type.presence
        )
      end
    end

    def forced_registration_args(registration)
      forced = {}
      forced["type"] = catalog.displayed_type_name(registration.type) if registration.type.present?
      forced["action"] = registration.target.value.to_s if registration.target.action?
      forced
    end

    def wrap_metric(tool, result)
      return success_result(result) if tool.catalog?

      render_handler_result(result)
    end
  end
end

require "recording_studio_mcp/dispatcher/handler_scope"
require "recording_studio_mcp/dispatcher/tree"
require "recording_studio_mcp/dispatcher/capability"
require "recording_studio_mcp/dispatcher/endpoint"
require "recording_studio_mcp/dispatcher/contexts"
require "recording_studio_mcp/dispatcher/capability_params"
require "recording_studio_mcp/dispatcher/contract_errors"
require "recording_studio_mcp/dispatcher/idempotency"
require "recording_studio_mcp/dispatcher/recordings"
require "recording_studio_mcp/dispatcher/results"
require "recording_studio_mcp/dispatcher/tool_errors"
