# frozen_string_literal: true

module RecordingStudioMcp
  module CatalogMetricTools
    module_function

    def parameters_for(entry)
      parameters = []
      append_window(parameters, entry)
      append_group(parameters, entry)
      append_filters(parameters, entry)
      parameters
    end

    def append_window(parameters, entry)
      return unless timeseries?(entry)

      parameters << period_parameter("from", FROM)
      parameters << period_parameter("to", TO)
      intervals = string_values(entry, :supported_intervals)
      return if intervals.empty?

      parameters << choice_parameter("interval", "Time-series bucket size.", intervals)
    end

    def append_group(parameters, entry)
      groups = string_values(entry, :group_by)
      return if groups.empty?

      parameters << choice_parameter("group_by", GROUP, groups)
    end

    def append_filters(parameters, entry)
      filters = Array(read_key(entry, :filters))
      return if filters.empty?

      parameters << filters_parameter(filters)
    end

    def filters_parameter(filters)
      {
        name: "filters", in: "query", required: false, description: FILTERS,
        schema: filters_schema(filters)
      }
    end

    def filters_schema(filters)
      {
        type: "object",
        additionalProperties: false,
        properties: filters.to_h { |filter| [read_key(filter, :name).to_sym, filter_property(filter)] }
      }
    end

    def timeseries?(entry)
      range = read_key(entry, :date_range)
      return supported_range?(range) if range.is_a?(Hash)

      read_key(entry, :result_type).to_s == "timeseries"
    end

    def supported_range?(range)
      value = range.fetch(:supported) { range["supported"] }
      value == true
    end

    def filter_property(filter)
      schema = filter_type_schema(read_key(filter, :type).to_s, Array(read_key(filter, :options)))
      label = read_key(filter, :label)
      schema[:description] = label.to_s if label.present?
      schema
    end

    def filter_type_schema(type, options)
      case type
      when "boolean" then { type: "boolean" }
      when "integer" then { type: "integer" }
      when "enum" then { type: "string", enum: options.map(&:to_s) }
      when "numeric_range", "date_range", "datetime_range" then { type: "object" }
      else { type: "string" }
      end
    end

    def period_parameter(name, description)
      {
        name: name, in: "query", required: false, description: description,
        schema: { type: "string", format: "date-time" }
      }
    end

    def choice_parameter(name, description, values)
      {
        name: name, in: "query", required: false, description: description,
        schema: { type: "string", enum: values }
      }
    end

    def string_values(entry, key)
      Array(read_key(entry, key)).map(&:to_s)
    end
    private_class_method :parameters_for, :append_window, :append_group, :append_filters, :filters_parameter,
                         :filters_schema, :timeseries?, :supported_range?, :filter_property, :filter_type_schema,
                         :period_parameter, :choice_parameter, :string_values
  end
end
