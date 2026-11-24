# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module TypeDescribeBlocks
        module_function

        def server_parent?(entry, context)
          type_name = entry["recordable_type"].to_s
          type_name.present? && RecordingStudioApi.server_create_parent?(type_name, api: context[:api_key])
        end

        def parent_block(entry)
          parent = entry["parent"]
          return if parent.blank?

          parts = []
          parts << "root #{parent['root']}" if parent.key?("root")
          parts << allowed_parents_part(parent) if parent.key?("allowed_parent_types")
          return if parts.empty?

          "Parents: #{parts.join('. ')}."
        end

        def relationships_block(entry)
          rels = Array(entry["relationships"])
          return if rels.empty?

          lines = rels.map { |rel| relationship_line(Internals.stringify(rel)) }
          (["Relationships:"] + lines).join("\n")
        end

        def capability_actions_block(entry, api_key)
          actions = Array(entry["capability_actions"])
          return if actions.empty?

          recordable_type = entry["recordable_type"].presence || entry["type"]
          lines = ["Capability actions:"]
          actions.each do |action|
            lines << capability_action_line(Internals.stringify(action), recordable_type, api_key)
          end
          lines.join("\n")
        end

        def allowed_parents_part(parent)
          types = Array(parent["allowed_parent_types"])
          return "allowed parent types none" if types.empty?

          "allowed parent types #{types.join(', ')}"
        end
        private_class_method :allowed_parents_part

        def relationship_line(rel)
          bits = [rel["name"]]
          bits << rel["source"] if rel["source"].present?
          bits << rel["child_type"] if rel["child_type"].present?
          bits << (rel["many"] ? "many" : "one") if rel.key?("many")
          line = "- #{bits.join(', ')}"
          return line if rel["description"].blank?

          "#{line}. #{rel['description']}"
        end
        private_class_method :relationship_line

        def capability_action_line(action, recordable_type, api_key)
          name = action["name"]
          line = "- #{name}"
          return line unless creates?(name, recordable_type, api_key)

          note = action["idempotency_key"].presence
          note ? "#{line}. #{note}" : line
        end
        private_class_method :capability_action_line

        def creates?(action_name, recordable_type, api_key)
          action = RecordingStudioApi.capability_action(action_name, api: api_key)
          return false if action.nil?
          return true if action.creates?

          registration = RecordingStudioApi.resource_handler_registration(
            recordable_type, action.name, api: api_key
          )
          registration.respond_to?(:creates?) && registration.creates?
        end
        private_class_method :creates?
      end
    end
  end
end
