# frozen_string_literal: true

module RecordingStudioMcp
  class Catalog
    module DescribeShape
      private

      def default_describe_payload(recordable_type, registration)
        describe_core(recordable_type, registration)
          .merge(describe_registry(recordable_type, registration))
          .compact
      end

      def describe_core(recordable_type, registration)
        {
          "type" => recordable_type,
          "description" => Documentation::Openapi::Schemas.registered_type_description(
            recordable_type, api
          ),
          "operations" => Array(registration&.operations).map(&:to_s),
          "writable_fields" => FieldSchema.for(recordable_type, registration),
          "capability_actions" => enabled_capability_actions(recordable_type)
        }
      end

      def describe_registry(recordable_type, registration)
        {
          "output_keys" => Array(registration&.output_keys).map(&:to_s),
          "fields" => field_names(registration),
          "relationships" => describe_relationships(registration),
          "allowed_children" => allowed_children(recordable_type, registration),
          "parent" => parent_rules(recordable_type)
        }
      end

      def apply_describe_payload(payload, type:, registration:)
        hook = RecordingStudioMcp.configuration.describe_payload
        return payload unless hook.respond_to?(:call)

        result = hook.call(payload, type: type, registration: registration, access_grant: access_grant)
        result.is_a?(Hash) ? result.deep_stringify_keys : payload
      end

      def field_names(registration)
        fields = registration&.fields
        return [] unless fields.respond_to?(:keys)

        fields.keys.map(&:to_s).sort
      end

      def describe_relationships(registration)
        rels = registration&.relationships
        return [] unless rels.respond_to?(:each)

        rels.sort_by { |name, _| name.to_s }.filter_map do |name, rel|
          relationship_details(name, rel) if advertised_relationship?(rel)
        end
      end

      def advertised_relationship?(rel)
        rel.child_type.blank? || registered_types.include?(rel.child_type)
      end

      def relationship_details(name, rel)
        {
          "name" => name.to_s,
          "source" => rel.source.to_s,
          "child_type" => rel.child_type,
          "many" => rel.many
        }.merge(relationship_options(rel)).compact
      end

      def relationship_options(rel)
        {
          "include" => include_policy(rel.include),
          "output_keys" => Array(rel.output_keys).map(&:to_s),
          "endpoints" => Array(rel.endpoints).map(&:to_s),
          "limit" => rel.limit,
          "description" => rel.description
        }
      end

      def include_policy(value)
        value.is_a?(Symbol) ? value.to_s : value
      end

      def allowed_children(recordable_type, registration)
        (relationship_child_types(registration) + child_types_from_parent_rules(recordable_type)).uniq.sort
      end

      def relationship_child_types(registration)
        rels = registration&.relationships
        return [] unless rels.respond_to?(:each)

        rels.filter_map { |_, rel| rel.child_type.presence }
            .select { |type| registered_types.include?(type) }
      end

      def child_types_from_parent_rules(recordable_type)
        return [] unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:allowed_parent_types_for)

        registered_types.select do |type|
          Array(RecordingStudio.allowed_parent_types_for(type)).map(&:to_s).include?(recordable_type)
        end
      end
    end
  end
end
