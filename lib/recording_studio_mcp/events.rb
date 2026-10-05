# frozen_string_literal: true

module RecordingStudioMcp
  module Events
    RECORDING_UPDATED = "recording updated"
    PATTERN = /\A[a-z0-9]+(?: [a-z0-9]+)*\z/
    LENGTH = (1..64)

    Registration = Data.define(:name)

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
  end
end
