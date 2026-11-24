# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def capability_input_params(args, action, named_tool: false)
      apply_capability_contract(action, capability_raw_params(args, action, named_tool: named_tool))
    end

    def capability_raw_params(args, action, named_tool:)
      body = stringify_keys(args)
      nested = stringify_keys(body["params"]).except(*FINGERPRINT_EXCLUDED_KEYS)
      raw = nested.merge(body.slice(*capability_root_keys(action, named_tool: named_tool)))
      raw.blank? ? {} : raw
    end

    def capability_root_keys(action, named_tool:)
      keys = capability_contract_keys(action)
      named_tool ? keys : keys - %w[type action id]
    end

    def apply_capability_contract(action, raw)
      raw = raw.except("parent_id", :parent_id) if server_action_parent?(action)
      normalized = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
      contract = request_contract_for(action)
      return normalized if contract.nil?

      result = contract.call(normalized)
      return result.value if result.success?

      raise_contract_failure!("Invalid input for #{invoked_tool_name}", contract, result)
    end

    def server_action_parent?(action)
      action.respond_to?(:server_parent?) && action.server_parent?
    end

    def request_contract_for(action)
      return catalog.action_request_contract(action) if catalog.respond_to?(:action_request_contract)
      return if action.nil?

      action.respond_to?(:request_input_contract) ? action.request_input_contract : action.input_contract
    end

    def invoked_tool_name
      @tool_name.to_s.empty? ? "capability_action" : @tool_name.to_s
    end

    def capability_contract_keys(action)
      SchemaFromContract.stringify(capability_contract_fields(action)).keys
    end

    def capability_contract_fields(action)
      contract = request_contract_for(action)
      return {} if contract.nil?

      payload = contract.respond_to?(:as_json) ? contract.as_json : contract
      Documentation::Openapi::ActionDocs.definition_fields(payload) || {}
    end
  end
end
