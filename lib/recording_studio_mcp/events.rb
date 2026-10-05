# frozen_string_literal: true

module RecordingStudioMcp
  module Events
    RECORDING_UPDATED = "recording updated"
    RECORDING_UPDATED_TRIGGER = :recording_updated
    PATTERN = /\A[a-z0-9]+(?: [a-z0-9]+)*\z/
    LENGTH = (1..64)

    class Definition
      attr_reader :trigger, :types, :filter

      def initialize
        @trigger = nil
        @types = nil
        @filter = nil
      end

      def on(name)
        @trigger = name&.to_sym
      end

      def types(*names)
        @types = names.flatten.map(&:to_s)
      end

      def if(&block) # rubocop:disable Naming/MethodName
        raise ArgumentError, "if must be a block" unless block

        @filter = block
      end
    end

    Registration = Data.define(:name, :trigger, :types, :filter) do
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

    def build_registration(name)
      parsed = parse(name)
      raise ArgumentError, "invalid event name" if parsed.nil?

      definition = Definition.new
      if block_given?
        yield(definition)
      elsif parsed == RECORDING_UPDATED
        definition.on(RECORDING_UPDATED_TRIGGER)
      end

      Registration.new(
        name: parsed,
        trigger: definition.trigger,
        types: definition.types,
        filter: definition.filter
      )
    end
  end
end
