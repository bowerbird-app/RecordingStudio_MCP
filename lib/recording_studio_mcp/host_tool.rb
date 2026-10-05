# frozen_string_literal: true

module RecordingStudioMcp
  class HostTool
    attr_reader :name, :title, :description, :read_only, :destructive, :idempotent,
                :required, :properties, :additional_properties, :handler

    def initialize(attributes)
      handler = attributes.fetch(:handler)
      raise ArgumentError, "handler must be callable" unless handler.respond_to?(:call)

      @name = attributes.fetch(:name).to_s
      @title = attributes.fetch(:title).to_s
      @description = attributes.fetch(:description).to_s
      @handler = handler
      @read_only = attributes.fetch(:read_only, true)
      @destructive = attributes.fetch(:destructive, false)
      @idempotent = attributes.fetch(:idempotent, true)
      @required = Array(attributes.fetch(:required, []))
      @properties = attributes.fetch(:properties, {})
      @additional_properties = attributes[:additional_properties]
    end

    def definition
      Tools.host_definition(self)
    end
  end
end
