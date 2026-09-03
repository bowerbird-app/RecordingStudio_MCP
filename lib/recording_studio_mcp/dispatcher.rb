# frozen_string_literal: true

require "action_controller"

module RecordingStudioMcp
  class Dispatcher
    RESOURCE_TOOLS = {
      "list" => :index,
      "show" => :show,
      "create" => :create,
      "update" => :update
    }.freeze
    WRITE_RESERVED_KEYS = %w[type parent_id id idempotency_key].freeze

    def self.call(tool_name:, arguments:, access_grant:, idempotency_key: nil)
      new(access_grant: access_grant, idempotency_key: idempotency_key).call(tool_name, arguments)
    end

    def initialize(access_grant:, idempotency_key: nil)
      @access_grant = access_grant
      @idempotency_key = idempotency_key
      @catalog = Catalog.for(access_grant)
    end

    def call(tool_name, arguments)
      name = tool_name.to_s
      args = stringify_keys(arguments)
      return error_result(unknown_tool_message(name)) unless Tools.known?(name)

      case name
      when "describe"
        success_result(catalog.describe(args["type"]))
      when "capability_action"
        dispatch_capability_action(args)
      else
        dispatch_resource(RESOURCE_TOOLS.fetch(name), args)
      end
    rescue RecordingStudioApi::AuthorizationError,
           RecordingStudioApi::NotFoundError,
           RecordingStudioApi::UnsupportedActionError,
           RecordingStudioApi::InvalidActionInputError,
           RecordingStudioApi::InvalidPaginationTokenError => e
      error_result(e.message)
    end

    private

    attr_reader :access_grant, :idempotency_key, :catalog

    def dispatch_resource(operation_name, args)
      recordable_type = catalog.resolve_type!(args["type"])
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      if registration && !registration.supports_operation?(operation_name)
        raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{recordable_type}"
      end

      operation = RecordingStudioApi.resource_action(operation_name, version: api_version, api: api_key)
      if operation.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      recording = load_recording(recordable_type, args["id"]) if %i[show update].include?(operation_name)
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
        idempotency_key: create_idempotency_key(args, operation_name)
      )
    end

    def action_context(recording, args, action)
      raw = stringify_keys(args["params"]).presence || {}
      normalized = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
      params =
        if action.input_contract.nil?
          normalized
        else
          contract_result = action.input_contract.call(normalized)
          unless contract_result.success?
            raise RecordingStudioApi::InvalidActionInputError, "Invalid input for action #{action.name}"
          end

          contract_result.value
        end

      RecordingStudioApi::ActionContext.new(
        recording: recording,
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording,
        params: params
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

    def load_recording(recordable_type, id)
      raise RecordingStudioApi::InvalidActionInputError, "id is required" if id.blank?

      recording = access_grant.accessible_recordings.find_by(id: id)
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
      "Unknown tool #{name}. Allowed tools: #{Tools::NAMES.join(', ')}"
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
