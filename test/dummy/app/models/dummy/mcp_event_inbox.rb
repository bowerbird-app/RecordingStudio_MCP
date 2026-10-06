# frozen_string_literal: true

module Dummy
  class McpEventInbox
    Delivery = Struct.new(:headers, :body, :verified, keyword_init: true)

    class << self
      def deliveries
        @deliveries ||= []
      end

      def record(headers:, body:, verified:)
        deliveries << Delivery.new(headers: headers, body: body, verified: verified)
      end

      def clear!
        @deliveries = []
      end
    end
  end
end
