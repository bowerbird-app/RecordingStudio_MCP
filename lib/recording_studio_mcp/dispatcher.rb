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

    def self.call(tool_name:, arguments:, access_grant:)
      new(access_grant: access_grant).call(tool_name, arguments)
    end

    def initialize(access_grant:)
      @access_grant = access_grant
    end

    def call(tool_name, arguments)
      name = tool_name.to_s
      args = stringify_keys(arguments)
      return error_result("Unknown tool #{name}") unless Tools.known?(name)

      if name == "capability_action"
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

    attr_reader :access_grant

    def dispatch_resource(operation_name, args)
      recordable_type = resolve_recordable_type!(args["type"])
      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: api_key)
      if registration && !registration.supports_operation?(operation_name)
        raise RecordingStudioApi::UnsupportedActionError, "#{operation_name} is not enabled for #{recordable_type}"
      end

      operation = RecordingStudioApi.resource_action(operation_name, version: api_version, api: api_key)
      if operation.nil?
        raise RecordingStudioApi::UnsupportedActionError, "Unknown API resource operation #{operation_name}"
      end

      recording = load_recording(recordable_type, args["id"]) if %i[show update].include?(operation_name)
      result = operation.handler.call(resource_context(recordable_type, args, recording: recording))
      success_result(result.fetch(:json))
    end

    def dispatch_capability_action(args)
      recordable_type = resolve_recordable_type!(args["type"])
      action_name = args["action"].to_s
      raise RecordingStudioApi::InvalidActionInputError, "action is required" if action_name.blank?

      action = RecordingStudioApi.capability_action(action_name, version: api_version, api: api_key)
      raise RecordingStudioApi::UnsupportedActionError, "Unknown API action #{action_name}" if action.nil?
      unless action.applicable_to?(recordable_type)
        raise RecordingStudioApi::UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}"
      end
      unless RecordingStudioApi.capability_action_enabled_for?(action, recordable_type, api: api_key)
        raise RecordingStudioApi::UnsupportedActionError, "#{action.name} is not enabled for #{recordable_type}"
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

    def resource_context(recordable_type, args, recording: nil)
      params = ActionController::Parameters.new(resource_params(recordable_type, args)).permit!
      request_params = ActionController::Parameters.new(write_params(args)).permit!

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
        idempotency_key: nil
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
        "include" => args["include"]
      }.compact
    end

    def write_params(args)
      payload = stringify_keys(args["attributes"])
      payload["parent_id"] = args["parent_id"] if args.key?("parent_id")
      payload
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

    def resolve_recordable_type!(type)
      raise RecordingStudioApi::InvalidActionInputError, "type is required" if type.blank?

      name = type.to_s
      return name if RecordingStudioApi.recordable_registration_for(name, api: api_key)

      from_resource = RecordingStudioApi.recordable_type_for_resource(name, api: api_key) ||
                      RecordingStudioApi.recordable_type_for_resource(name.pluralize, api: api_key)
      return from_resource if from_resource.present?

      raise RecordingStudioApi::NotFoundError, "Unknown API resource #{name}"
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
      access_grant.api_client&.api_key.presence || "public"
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

    def success_result(payload)
      {
        content: [{ type: "text", text: JSON.generate(payload) }],
        isError: false
      }
    end

    def error_result(message)
      {
        content: [{ type: "text", text: message.to_s }],
        isError: true
      }
    end
  end
end
