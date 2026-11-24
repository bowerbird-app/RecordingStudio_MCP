# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def sibling_tool_name(recordable_type, operation)
      server = catalog.resolved_server
      return if server.nil? || operation.blank?

      named = server.tools.each_value.find { |tool| named_sibling?(tool, recordable_type, operation) }
      return named.name if named

      generic_sibling(server, recordable_type, operation)
    end

    def named_sibling?(tool, recordable_type, operation)
      registration = tool.registration
      return false if registration.nil? || registration.type.to_s != recordable_type.to_s
      return false if Catalogs::GENERIC_NAMES.include?(tool.name)

      same_operation?(registration.target, operation)
    end

    def same_operation?(target, operation)
      return false if target.nil?
      return target.value.to_sym == operation.to_sym if target.operation?
      return target.value.to_s == operation.to_s if target.action?

      false
    end

    def generic_sibling(server, recordable_type, operation)
      name = Tools::TREE_OPERATION_TOOLS[operation.to_sym]
      return unless name && server.tool?(name)

      registration = RecordingStudioApi.recordable_registration_for(recordable_type, api: catalog.api)
      name if registration&.supports_operation?(operation)
    end
  end
end
