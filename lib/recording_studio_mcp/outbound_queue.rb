# frozen_string_literal: true

module RecordingStudioMcp
  class OutboundQueue
    def initialize(limit:)
      @limit = limit
      @items = []
    end

    def push(item)
      return :full if @items.length >= @limit

      @items << item
      :ok
    end

    def shift
      @items.shift
    end

    def any?
      @items.any?
    end

    def empty?
      @items.empty?
    end
  end
end
