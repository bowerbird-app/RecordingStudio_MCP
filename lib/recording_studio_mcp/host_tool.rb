# frozen_string_literal: true

module RecordingStudioMcp
  class HostTool
    attr_reader :name, :title, :description, :read_only, :destructive, :idempotent,
                :required, :properties, :additional_properties, :handler

    def initialize(name:, title:, description:, handler:, read_only: true, destructive: false,
                   idempotent: true, required: [], properties: {}, additional_properties: nil)
      raise ArgumentError, "handler must be callable" unless handler.respond_to?(:call)

      @name = name.to_s
      @title = title.to_s
      @description = description.to_s
      @handler = handler
      @read_only = read_only
      @destructive = destructive
      @idempotent = idempotent
      @required = Array(required)
      @properties = properties
      @additional_properties = additional_properties
    end

    def definition
      Tools.host_definition(self)
    end
  end
end
