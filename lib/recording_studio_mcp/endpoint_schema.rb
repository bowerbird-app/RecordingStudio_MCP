# frozen_string_literal: true

module RecordingStudioMcp
  class EndpointSchema
    CONTRACT_TYPE_MAP = {
      string: "string",
      integer: "integer",
      float: "number",
      boolean: "boolean",
      array: "array",
      hash: "object",
      symbol: "string"
    }.freeze

    def self.build(endpoint)
      new(endpoint).build
    end

    def initialize(endpoint)
      @endpoint = endpoint
    end

    def build
      path = path_properties
      contract = contract_properties
      properties = contract.fetch(:properties).merge(path.fetch(:properties))
      required = (path.fetch(:required) + contract.fetch(:required)).uniq

      schema = {
        type: "object",
        properties: properties,
        required: required
      }
      schema[:additionalProperties] = false if reject_unknown?
      schema
    end

    private

    attr_reader :endpoint

    def path_properties
      properties = {}
      required = []

      endpoint.path_segments.each do |segment|
        next unless segment.start_with?(":")

        name = segment.delete_prefix(":")
        properties[name.to_sym] = {
          type: "string",
          description: path_description(name)
        }
        required << name
      end

      { properties: properties, required: required }
    end

    def path_description(name)
      param = endpoint.openapi_path_parameters.find { |entry| entry[:name].to_s == name }
      param&.[](:description).presence || "Path parameter #{name}."
    end

    def contract_properties
      return { properties: {}, required: [] } if contract_fields.blank?

      properties = {}
      required = []

      contract_fields.each do |field_name, rules|
        rules = rules.to_h.deep_symbolize_keys
        name = field_name.to_sym
        property = { type: CONTRACT_TYPE_MAP.fetch(rules[:type]&.to_sym, "string") }
        property[:enum] = Array(rules[:enum]) if rules[:enum].present?
        property[:description] = rules[:description] if rules[:description].present?
        properties[name] = property
        required << name.to_s if rules[:required]
      end

      { properties: properties, required: required }
    end

    def contract_definition
      endpoint.input_contract&.as_json
    end

    def contract_fields
      definition = contract_definition
      return unless definition

      definition[:fields] || definition["fields"]
    end

    def reject_unknown?
      definition = contract_definition
      return false unless definition

      if definition.key?(:reject_unknown)
        definition[:reject_unknown]
      elsif definition.key?("reject_unknown")
        definition["reject_unknown"]
      else
        true
      end
    end
  end
end
