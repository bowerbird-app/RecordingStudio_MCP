# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def raise_contract_failure!(label, contract, result)
      raise RecordingStudioApi::InvalidActionInputError.new(
        contract_failure_message(label, contract, result),
        details: result.errors
      )
    end

    def contract_failure_message(label, contract, result)
      [label, annotated_contract_errors(contract, result.errors)].compact.join(": ")
    end

    def annotated_contract_errors(contract, errors)
      Array(errors).map { |error| annotate_contract_error(contract, error) }.to_sentence.presence
    end

    def annotate_contract_error(contract, error)
      text = error.to_s
      description = contract_field_description(contract, text[/\A([A-Za-z0-9_]+)/, 1])
      return text if description.blank?

      "#{text}. #{description}"
    end

    def contract_field_description(contract, name)
      return if name.blank?

      rules = contract_field_rules(contract, name)
      return unless rules.is_a?(Hash)

      (rules[:description] || rules["description"]).to_s.presence
    end

    def contract_field_rules(contract, name)
      payload = contract.respond_to?(:as_json) ? contract.as_json : contract
      return unless payload.is_a?(Hash)

      fields = payload[:fields] || payload["fields"]
      return unless fields.is_a?(Hash)

      fields[name.to_sym] || fields[name.to_s]
    end
  end
end
