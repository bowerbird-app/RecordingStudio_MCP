# frozen_string_literal: true

module RecordingStudioMcp
  class Catalogs
    module Lookups
      def resolve_lookup(api, registration)
        return generic_operation_lookup(api, registration) if generic_operation?(registration)

        lookup = lookup_for(api, registration)
        [lookup, lookup&.sensitive == true]
      end

      def generic_operation?(registration)
        registration.generic? && OPERATION_TOOLS.key?(registration.name)
      end

      def generic_operation_lookup(api, registration)
        operation = OPERATION_TOOLS.fetch(registration.name)
        lookups = operation_lookups(api, operation)
        assert_fields!(registration, lookups.first)
        [lookups.first, lookups.any? { |item| item.sensitive == true }]
      end

      def lookup_for(api, registration)
        kwargs = lookup_kwargs(api, registration)
        if kwargs.nil?
          assert_fields!(registration, nil) if registration.generic?
          return
        end

        result = RecordingStudioApi.lookup(**kwargs)
        raise RecordingStudioApi::ConfigurationError, unknown_api_target(registration, api) if result.nil?

        assert_fields!(registration, result)
        result
      end

      def lookup_kwargs(api, registration)
        target = lookup_target(registration)
        return unless target

        { api: api, recordable_type: registration.type.presence }.compact.merge(target)
      end

      def lookup_target(registration)
        kind = registration.target.kind
        return { endpoint: registration.target.value } if kind == :endpoint
        return if registration.generic?

        { kind => registration.target.value } if %i[operation action].include?(kind)
      end

      def unknown_api_target(registration, api)
        "MCP tool #{registration.name} names API #{registration.target.kind} #{registration.target.value} " \
          "that is not on #{api}"
      end

      def assert_fields!(registration, lookup)
        registration.input.each_key do |field|
          key = field.to_s
          next if SchemaFromContract::PROTOCOL_KEYS.include?(key)
          next if !registration.generic? && SchemaFromContract.stringify(lookup&.input_contract).key?(key)

          raise RecordingStudioApi::ConfigurationError, unknown_input_field(registration, key)
        end
      end

      def unknown_input_field(registration, field)
        if registration.generic?
          "MCP tool #{registration.name} field #{field} is not a protocol key"
        else
          "MCP tool #{registration.name} field #{field} is not on the API contract"
        end
      end

      def operation_lookups(api, operation)
        api_type_names(api).filter_map do |type_name|
          RecordingStudioApi.lookup(api: api, recordable_type: type_name, operation: operation)
        end
      end

      def api_type_names(api)
        RecordingStudioApi.configuration.fetch_api(api).recordable_registry.to_h.keys.map(&:to_s)
      end

      def metric_tool?(api, name)
        metric_by_name(api, name).present?
      end

      def metric_by_name(api, name, ignore_allowlist: false)
        catalog = Catalog.new(api: api, server: false)
        recordable = MetricTools.collect_recordable(catalog)
        catalog_tools = MetricTools.collect_catalog(catalog, nil, ignore_allowlist: ignore_allowlist)
        (recordable + catalog_tools).find { |metric| metric.name.to_s == name }
      end

      def excluded_catalog_metric?(api, name)
        metric_by_name(api, name, ignore_allowlist: true)&.catalog? && metric_by_name(api, name).nil?
      end
    end
  end
end
