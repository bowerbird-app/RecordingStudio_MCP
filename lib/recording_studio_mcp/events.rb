# frozen_string_literal: true

module RecordingStudioMcp
  module Events
    RECORDING_UPDATED = "recording updated"
    RECORDING_UPDATED_TRIGGER = :recording_updated
    PATTERN = /\A[a-z0-9]+(?: [a-z0-9]+)*\z/
    LENGTH = (1..64)

    class Definition
      attr_reader :trigger, :allowed_types, :filter, :webhook

      def initialize
        @trigger = nil
        @allowed_types = nil
        @filter = nil
        @webhook = nil
      end

      def on(name)
        @trigger = name&.to_sym
      end

      def types(*names)
        @allowed_types = names.flatten.map(&:to_s)
      end

      def if(&block)
        raise ArgumentError, "if must be a block" unless block

        @filter = block
      end

      def webhook_event(name, description:, arguments:, payload:)
        @webhook = Webhook.build(name: name, description: description, arguments: arguments, payload: payload)
      end
    end

    WebhookName = Data.define(:name, :description, :arguments_schema, :payload_schema)
    WEBHOOK_NAME_PATTERN = /\A[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+\z/
    WEBHOOK_NAME_LENGTH = (1..128)

    class Webhook
      def self.build(name:, description:, arguments:, payload:)
        parsed = parse_name(name)
        raise ArgumentError, "invalid webhook event name" if parsed.nil?
        raise ArgumentError, "description is required" unless description.is_a?(String) && description.present?
        raise ArgumentError, "arguments must be a JSON Schema object" unless schema_object?(arguments)
        raise ArgumentError, "payload must be a JSON Schema object" unless schema_object?(payload)

        WebhookName.new(
          name: parsed,
          description: description,
          arguments_schema: deep_freeze(arguments),
          payload_schema: deep_freeze(payload)
        )
      end

      def self.parse_name(name)
        return nil unless name.is_a?(String)
        return nil unless WEBHOOK_NAME_LENGTH.cover?(name.length)
        return nil unless WEBHOOK_NAME_PATTERN.match?(name)

        name
      end

      def self.schema_object?(schema)
        schema.is_a?(Hash) && schema.stringify_keys["type"] == "object"
      end
      private_class_method :schema_object?

      def self.deep_freeze(value)
        case value
        when Hash
          value.to_h { |key, entry| [key.is_a?(String) ? key : key.to_s, deep_freeze(entry)] }.freeze
        when Array
          value.map { |entry| deep_freeze(entry) }.freeze
        else
          value.freeze
        end
      end
      private_class_method :deep_freeze
    end

    RECORDING_UPDATED_WEBHOOK = Webhook.build(
      name: "recording.updated",
      description: "An item the connected account can read was saved.",
      arguments: {
        "type" => "object",
        "properties" => {
          "recording_id" => {
            "type" => "string",
            "description" => "ID of the item to watch."
          }
        },
        "required" => ["recording_id"],
        "additionalProperties" => false
      },
      payload: {
        "type" => "object",
        "properties" => {
          "recording_id" => { "type" => "string" },
          "uri" => { "type" => "string" }
        },
        "required" => %w[recording_id uri],
        "additionalProperties" => false
      }
    )

    Registration = Data.define(:name, :trigger, :types, :filter, :webhook) do
      def built_in_save?
        trigger == RECORDING_UPDATED_TRIGGER
      end

      def matches_recording?(recording)
        return false unless type_allowed?(recording)
        return false unless filter_allows?(recording)

        true
      end

      def type_allowed?(recording)
        return true if types.nil? || types.empty?

        types.include?(recording.recordable_type.to_s)
      end
      private :type_allowed?

      def filter_allows?(recording)
        return true if filter.nil?

        filter.call(recording) == true
      end
      private :filter_allows?
    end

    class Catalog
      include Enumerable

      def self.empty
        new({})
      end

      def initialize(entries)
        @entries = entries.freeze
      end

      def add(registration)
        self.class.new(@entries.merge(registration.name => registration))
      end

      def registered?(name)
        @entries.key?(name.to_s)
      end

      def fetch(name)
        @entries[name.to_s]
      end

      def fetch_webhook(name)
        find { |registration| registration.webhook&.name == name.to_s }
      end

      def each(&)
        @entries.each_value(&)
      end

      def empty?
        @entries.empty?
      end
    end

    module_function

    def parse(name)
      return nil unless name.is_a?(String)
      return nil unless LENGTH.cover?(name.length)
      return nil unless PATTERN.match?(name)

      name
    end

    def build_registration(name, &)
      parsed = parse(name)
      raise ArgumentError, "invalid event name" if parsed.nil?

      definition = filled_definition(parsed, &)
      Registration.new(
        name: parsed,
        trigger: definition.trigger,
        types: definition.allowed_types,
        filter: definition.filter,
        webhook: definition.webhook || default_webhook(parsed)
      )
    end

    def default_webhook(parsed)
      parsed == RECORDING_UPDATED ? RECORDING_UPDATED_WEBHOOK : nil
    end
    private_class_method :default_webhook

    def filled_definition(parsed, &)
      definition = Definition.new
      if block_given?
        yield(definition)
      elsif parsed == RECORDING_UPDATED
        definition.on(RECORDING_UPDATED_TRIGGER)
      end
      definition
    end
    private_class_method :filled_definition
  end
end
