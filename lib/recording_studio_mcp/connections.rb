# frozen_string_literal: true

require "securerandom"

module RecordingStudioMcp
  module Connections
    module_function

    def open(protocol_version:, access_grant:, subscription_id: nil)
      connection = Connection.new(
        id: new_id,
        protocol_version: protocol_version,
        access_grant: access_grant,
        subscription_id: subscription_id
      )
      store[connection.id] = connection
      connection
    end

    def fetch(id)
      return if id.blank?

      store[id.to_s]
    end

    def drop(id)
      connection = store.delete(id.to_s)
      connection&.finish!
      connection
    end

    def each(&)
      store.each_value(&)
    end

    def to_a
      store.values
    end

    def clear!
      store.each_value(&:finish!)
      store.clear
    end

    def new_id
      SecureRandom.urlsafe_base64(18)
    end
    private_class_method :new_id

    def store
      @store ||= ConcurrentMap.new
    end
    private_class_method :store

    class ConcurrentMap
      def initialize
        @mutex = Mutex.new
        @entries = {}
      end

      def [](key)
        @mutex.synchronize { @entries[key] }
      end

      def []=(key, value)
        @mutex.synchronize { @entries[key] = value }
      end

      def delete(key)
        @mutex.synchronize { @entries.delete(key) }
      end

      def values
        @mutex.synchronize { @entries.values.dup }
      end

      def each_value(&)
        values.each(&)
      end

      def clear
        @mutex.synchronize { @entries.clear }
      end
    end
    private_constant :ConcurrentMap
  end
end
