# frozen_string_literal: true

module RecordableMetricToolHelpers
  # metrics_for constantizes these names and compares the registered model class.
  # rubocop:disable Lint/EmptyClass
  class Folder; end
  class Page; end
  # rubocop:enable Lint/EmptyClass

  FOLDER = "RecordableMetricToolHelpers::Folder"
  PAGE = "RecordableMetricToolHelpers::Page"

  def with_recordable_metric_registry
    RecordingStudioMetrics.registry.reset!
    yield
  ensure
    RecordingStudioMetrics.registry.reset!
    if RecordingStudioMcp.const_defined?(:UsageLog, false)
      RecordingStudioMcp::Metrics.register!
    end
  end

  def register_folder_and_page_metrics
    RecordingStudioApi.register_recordable_type_api(
      FOLDER,
      serializer: ->(*) { { name: "Ada" } },
      output_keys: %i[name],
      writable_attributes: %i[name],
      operations: %i[index show create update],
      metrics: %w[folders.total folders.created_over_time]
    )
    RecordingStudioApi.register_recordable_type_api(
      PAGE,
      serializer: ->(*) { { title: "Note" } },
      output_keys: %i[title],
      writable_attributes: %i[title],
      operations: %i[index show create update],
      metrics: %w[pages.total]
    )
    register_folder_metric_definitions
    register_page_metric_definitions
  end

  def register_folder_metric_definitions
    RecordingStudioMetrics.register(:folders, model: RecordableMetricToolHelpers::Folder, blast_radius: :root) do
      count :total, title: "Folders", description: "How many folders are in this scope."
      timeseries :created_over_time,
                 title: "Created over time",
                 description: "Folders created in the window.",
                 field: :created_at,
                 intervals: %i[day week],
                 group_by: %i[name]
    end
  end

  def register_page_metric_definitions
    RecordingStudioMetrics.register(:pages, model: RecordableMetricToolHelpers::Page, blast_radius: :root) do
      count :total, title: "Pages", description: "How many pages are in this scope."
    end
  end
end
