# frozen_string_literal: true

module RecordingStudioMcp
  module MetricTools
    module RegisteredEntry
      FROM = "Inclusive period start, as an ISO-8601 date-time. start must match from when both are sent. " \
             "start_at is the fallback."
      TO = "Exclusive period end, as an ISO-8601 date-time. end must match to when both are sent. " \
           "end_at is the fallback."
      SCALAR_FROM = "Inclusive start for this count, applied on the metric field before execute. " \
                    "There is no timezone query parameter."
      SCALAR_TO = "Exclusive end for this count, applied on the metric field before execute."
      GROUP = "Grouping column for this metric. Do not allowlist a column that holds personal data. " \
              "Groups under min_group_size fold into other."

      module_function

      def build(registration, definition)
        RecordingStudioApi::MetricEntry.new(
          name: definition.identifier,
          description: definition.description.presence || definition.title,
          parameters: parameters_for(registration, definition),
          unit: definition.unit,
          title: definition.title.presence || definition.name.to_s,
          timezone: RecordingStudioMetrics.configuration.default_timezone,
          freshness: { cached: false }
        )
      end

      def parameters_for(registration, definition)
        [
          *window_parameters(definition),
          *group_parameters(definition),
          *RecordingStudioApi::Services::DocumentationCatalog.filter_query_parameters(
            registration.filterable_attributes
          )
        ]
      end

      def window_parameters(definition)
        return timeseries_window(definition) if definition.result_type == :timeseries
        return scalar_window if definition.field.present?

        []
      end

      def timeseries_window(definition)
        [
          period_parameter("from", FROM),
          period_parameter("to", TO),
          choice_parameter("interval", "Time-series bucket size.", definition.intervals)
        ]
      end

      def scalar_window
        [
          period_parameter("from", SCALAR_FROM),
          period_parameter("to", SCALAR_TO)
        ]
      end

      def group_parameters(definition)
        return [] if definition.group_by.empty?

        [choice_parameter("group_by", GROUP, definition.group_by)]
      end

      def period_parameter(name, description)
        {
          name: name,
          in: "query",
          required: false,
          description: description,
          schema: { type: "string", format: "date-time" }
        }
      end

      def choice_parameter(name, description, values)
        schema = { type: "string" }
        schema[:enum] = values.map(&:to_s) if values.any?
        {
          name: name,
          in: "query",
          required: false,
          description: description,
          schema: schema
        }
      end
    end
  end
end
