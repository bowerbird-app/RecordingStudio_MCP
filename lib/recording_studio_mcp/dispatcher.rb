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
      name = tool_name.to_s
      args = stringify_keys(arguments)
      return error_result(unknown_tool_message(name)) unless surface.known?(name)

      if surface.tree_tool?(name)
        dispatch_tree(name, args)
      else
        dispatch_endpoint(surface.endpoint_for(name), args)
      end
    rescue RecordingStudioApi::AuthorizationError,
           RecordingStudioApi::NotFoundError,
           RecordingStudioApi::UnsupportedActionError,
           RecordingStudioApi::InvalidActionInputError,
           RecordingStudioApi::InvalidPaginationTokenError => e
      error_result(e.message)
    end

    private

    attr_reader :access_grant, :idempotency_key, :request_context, :catalog, :surface

    def dispatch_tree(name, args)
      case name
      when "describe"
        success_result(catalog.describe(args["type"]))
      when "capability_action"
        dispatch_capability_action(args)
      else
        dispatch_resource(RESOURCE_TOOLS.fetch(name), args)
      end
    end

    def dispatch_endpoint(endpoint, args)
      context = RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording,
        params: endpoint_params(endpoint, args),
        progress_reporter: progress_reporter
      )
      result = endpoint.handler.call(context)
      success_result(serialize_endpoint_result(endpoint, result))
    end

    def endpoint_params(endpoint, args)
      apply_endpoint_contract(endpoint, merge_endpoint_args(endpoint, args))
    end

    def merge_endpoint_args(endpoint, args)
      path_keys = endpoint_path_keys(endpoint)
      require_endpoint_path_args!(path_keys, args)
      captures = path_keys.to_h { |key| [key.to_sym, args[key]] }
      remaining = stringify_keys(args).except(*path_keys)
      remaining = remaining.deep_symbolize_keys if remaining.respond_to?(:deep_symbolize_keys)
      remaining.merge(captures)
    end

    def endpoint_path_keys(endpoint)
      endpoint.path_segments.filter_map do |segment|
        segment.delete_prefix(":") if segment.start_with?(":")
      end
    end

    def require_endpoint_path_args!(path_keys, args)
      path_keys.each do |key|
        raise RecordingStudioApi::InvalidActionInputError, "#{key} is required" if args[key].blank?
      end
    end

    def apply_endpoint_contract(endpoint, merged)
      return merged if endpoint.input_contract.nil?

      contract_result = endpoint.input_contract.call(merged)
      return contract_result.value if contract_result.success?

      raise RecordingStudioApi::InvalidActionInputError.new(
        "Invalid input for endpoint #{endpoint.name}",
        details: contract_result.errors
      )
    end

    def serialize_endpoint_result(endpoint, result)
      serializer = endpoint.serializer
      return result if serializer.nil?

      serializer.call(result)
    end

    def dispatch_resource(operation_name, args)
      recordable_type = catalog.resolve_type!(args["type"])
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      if registration && !registration.supports_operation?(operation_name)
        raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{recordable_type}"
      end

      handler = RecordingStudioApi.resource_handler(recordable_type, operation_name, api: api_key)
      if handler
        return render_handler_result(
          handler.call(resource_context(recordable_type, args, recording: nil, operation_name: operation_name))
        )
      end

      operation = RecordingStudioApi.resource_action(operation_name, version: api_version, api: api_key)
      if operation.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      recording = builtin_member_recording_for(operation_name, recordable_type, args["id"])
      result = operation.handler.call(
        resource_context(recordable_type, args, recording: recording, operation_name: operation_name)
      )
      success_result(result.fetch(:json))
    end

    def dispatch_capability_action(args)
      recordable_type = catalog.resolve_type!(args["type"])
      action_name = args["action"].to_s
      raise RecordingStudioApi::InvalidActionInputError, "action is required" if action_name.blank?

      action = RecordingStudioApi.capability_action(action_name, version: api_version, api: api_key)
      unless action && RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: api_key)
        raise RecordingStudioApi::UnsupportedActionError, catalog.unknown_action_message(action_name, recordable_type)
      end

      handler = RecordingStudioApi.resource_handler(recordable_type, action.name, api: api_key)
      if handler
        return render_handler_result(handler.call(action_context(nil, args, action, recordable_type: recordable_type)))
      end

      recording = load_recording(recordable_type, args["id"])
      context = action_context(recording, args, action)
      required_role = RecordingStudioApi.configuration.capability_action_role_for(
        action: action,
        recording: recording,
        api_client: access_grant.api_client,
        access_grant: access_grant
      )
      access_grant.authorize!(recording: recording, role: required_role) if required_role.present?

      result = action.handler.call(context)
      payload = serialize_capability_result(action, result)
      success_result(payload)
    end

    def builtin_member_recording_for(operation_name, recordable_type, id)
      case operation_name
      when :show, :update
        load_recording(recordable_type, id)
      when :destroy
        load_recording(recordable_type, id, include_trashed: true)
      end
    end

    def render_handler_result(result)
      json = result.fetch(:json)
      status = result.fetch(:status, :ok)
      return success_result(json) if SUCCESS_STATUS_RANGE.cover?(Rack::Utils.status_code(status))

      error_result(handler_error_message(json))
    end

    def handler_error_message(json)
      payload = stringify_payload(json)
      if payload.is_a?(Hash)
        message = payload.dig("error", "message") || payload["message"]
        return message if message.present?
        return payload["error"] if payload["error"].is_a?(String)
      end

      payload.is_a?(Hash) ? JSON.generate(payload) : payload.to_s
    end

    def resource_context(recordable_type, args, recording: nil, operation_name: nil)
      params = ActionController::Parameters.new(resource_params(recordable_type, args)).permit!
      request_params = ActionController::Parameters.new(write_params(recordable_type, args, operation_name)).permit!

      RecordingStudioApi::ResourceOperationContext.new(
        recording: recording,
        recordable_type: recordable_type,
        resource_name: RecordingStudioApi.resource_name_for(recordable_type),
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording,
        api_version: api_version,
        params: params,
        request_params: request_params,
        scoped_recordings: access_grant.accessible_recordings,
        parent_recording: nil,
        idempotency_key: create_idempotency_key(args, operation_name),
        progress_reporter: progress_reporter,
        id: args["id"],
        parent_id: args["parent_id"],
        relationship_id: nil
      )
    end

    def action_context(recording, args, action, recordable_type: nil)
      params = capability_input_params(args, action)

      RecordingStudioApi::ActionContext.new(
        recording: recording,
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording,
        params: params,
        progress_reporter: progress_reporter,
        id: args["id"],
        recordable_type: recordable_type
      )
    end

    def resource_params(recordable_type, args)
      {
        "resource" => RecordingStudioApi.resource_name_for(recordable_type),
        "id" => args["id"],
        "q" => args["q"],
        "limit" => args["limit"],
        "sort" => args["sort"],
        "order" => args["order"],
        "filter" => args["filter"],
        "include" => args["include"],
        "pagination_token" => args["pagination_token"]
      }.compact
    end

    def write_params(recordable_type, args, operation_name)
      return {} unless %i[create update].include?(operation_name)

      if args.key?("attributes")
        raise RecordingStudioApi::InvalidActionInputError,
              "Send writable fields at the request root, not inside attributes"
      end

      payload = stringify_keys(args).except(*WRITE_RESERVED_KEYS)
      allowed = catalog.writable_fields(recordable_type)
      unknown = payload.keys - allowed
      if unknown.any?
        allowed_sentence = allowed.any? ? allowed.join(", ") : "(none)"
        raise RecordingStudioApi::InvalidActionInputError,
              "Unknown fields #{unknown.sort.join(', ')}. Writable fields for #{recordable_type}: #{allowed_sentence}"
      end

      payload["parent_id"] = args["parent_id"] if args.key?("parent_id")
      payload
    end

    def create_idempotency_key(args, operation_name)
      return unless operation_name == :create

      args["idempotency_key"].presence || idempotency_key
    end

    def capability_input_params(args, action)
      raw = stringify_keys(args["params"]).presence || {}
      normalized = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
      return normalized if action.input_contract.nil?

      contract_result = action.input_contract.call(normalized)
      unless contract_result.success?
        raise RecordingStudioApi::InvalidActionInputError, "Invalid input for action #{action.name}"
      end

      contract_result.value
    end

    def load_recording(recordable_type, id, include_trashed: false)
      raise RecordingStudioApi::InvalidActionInputError, "id is required" if id.blank?

      recordings =
        if include_trashed
          access_grant.accessible_recordings(include_trashed: true)
        else
          access_grant.accessible_recordings
        end
      recording = recordings.find_by(id: id)
      raise RecordingStudioApi::NotFoundError, "Resource was not found in this API scope" if recording.nil?
      unless recording.recordable_type == recordable_type
        raise RecordingStudioApi::NotFoundError, "Resource type does not match #{recordable_type}"
      end

      recording
    end

    def serialize_capability_result(action, result)
      return result.fetch(:json) if result.is_a?(Hash) && result.key?(:json)

      serializer = action.serializer || RecordingStudioApi::Serializers::ResourceRecordingSerializer
      if serializer == RecordingStudioApi::Serializers::ResourceRecordingSerializer
        return serializer.call(result, version: api_version, api: api_key)
      end

      serializer.call(result)
    end

    def progress_reporter
      request_context&.progress_reporter
    end

    def api_key
      catalog.api
    end

    def api_version
      RecordingStudioApi.default_api_version(api: api_key)
    end

    def stringify_keys(value)
      return {} if value.blank?
      return value.to_unsafe_h.stringify_keys if value.respond_to?(:to_unsafe_h)
      return value.to_h.stringify_keys if value.respond_to?(:to_h)

      {}
    end

    def unknown_tool_message(name)
      allowed = surface.tool_names
      suffix = allowed.any? ? allowed.join(", ") : "(none)"
      "Unknown tool #{name}. Allowed tools: #{suffix}"
    end

    def success_result(payload)
      json = stringify_payload(payload)
      {
        content: [{ type: "text", text: JSON.generate(json) }],
        structuredContent: json,
        isError: false
      }
    end

    def stringify_payload(payload)
      JSON.parse(JSON.generate(payload))
    rescue JSON::GeneratorError, TypeError
      payload
    end

    def error_result(message)
      {
        content: [{ type: "text", text: message.to_s }],
        isError: true
      }
    end
  end
end
