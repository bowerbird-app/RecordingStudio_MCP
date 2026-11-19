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
      normalized = raw.respond_to?(:deep_symbolize_keys) ? raw.deep_symbolize_keys : raw
      return normalized if action.input_contract.nil?

      result = action.input_contract.call(normalized)
      return result.value if result.success?

      raise RecordingStudioApi::InvalidActionInputError, "Invalid input for action #{action.name}"
    end

    def capability_contract_keys(action)
      SchemaFromContract.stringify(capability_contract_fields(action)).keys
    end

    def capability_contract_fields(action)
      contract = action.input_contract
      return {} if contract.nil?

      payload = contract.respond_to?(:as_json) ? contract.as_json : contract
      return {} unless payload.respond_to?(:to_h)

      hash = payload.to_h
      hash[:fields] || hash["fields"] || hash
    end
  end
end
