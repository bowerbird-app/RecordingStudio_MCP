# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_metrics_register_with_operations_expose_and_admin_view
    metrics = File.read(File.expand_path("../lib/recording_studio_mcp/metrics.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_mcp/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_mcp.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))

    assert_includes metrics, "RecordingStudioMetrics.register"
    assert_includes metrics, ":mcp_calls"
    assert_includes metrics, "UsageDailyMetric"
    assert_includes metrics, "timeseries :over_time"
    assert_includes metrics, "value_field: :call_count"
    assert_includes metrics, "timeseries :failed_over_time"
    assert_includes metrics, "value_field: :failed_count"
    assert_includes metrics, "breakdown :by_tool"
    assert_includes metrics, "breakdown :failed_by_tool"
    assert_includes metrics, 'method_name: "tools/call"'
    assert_includes metrics, "field: :subject_name"
    assert_includes metrics, "breakdown :by_method"
    assert_includes metrics, "field: :method_name"
    assert_includes metrics, "sum :rate_limited"
    assert_includes metrics, "field: :rate_limited_count"
    assert_includes metrics, ":mcp_subscriptions"
    assert_includes metrics, "EventSubscription"
    assert_includes metrics, "count :failing"
    assert_includes metrics, "cacheable: false"
    assert_includes metrics, "EventSubscription.failing"
    assert_includes File.read(File.expand_path("../app/models/recording_studio_mcp/event_subscription.rb", __dir__)),
                    "failure_count > 0"
    assert_includes metrics, "blast_radius: :site"
    assert_includes metrics, "expose: EXPOSE"
    assert_includes metrics, "api: [API]"
    assert_includes metrics, "API = :operations"
    assert_includes metrics, "Api::Access.can_view?"
    refute_includes metrics, "RecordingStudioAccessible.authorized?"
    refute_includes metrics, "access_recording_resolver"
    refute_includes metrics, "site_admin_recording_resolver"
    refute_includes metrics, "ADMIN_CONTEXT"
    refute_includes metrics, "Struct.new"
    refute_includes metrics, "RecordingStudioMetrics::Api.register!"
    refute_includes metrics, "respond_to?"
    refute_includes metrics, "rescue"

    access = File.read(File.expand_path("../lib/recording_studio_mcp/api/access.rb", __dir__))
    assert_includes access, "def can_view?"
    assert_includes access, "RecordingStudioAccessible.authorized?"
    assert_includes access, "role: :view"
    assert_includes access, "access_recording_resolver"
    refute_includes access, "Struct.new"
    refute_includes access, "ADMIN_CONTEXT"
    refute_includes access, "respond_to?"
    refute_includes access, "rescue"

    assert_includes engine, 'initializer "recording_studio_mcp.metrics"'
    assert_includes engine, "RecordingStudioMcp::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"

    assert_includes gemspec, 'spec.add_dependency "recording_studio_metrics", ">= 0.3.0", "< 0.6"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_logs", ">= 0.5.0", "< 0.6"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_api", ">= 0.11.0", "< 0.17"'
    assert_includes engine, 'initializer "recording_studio_mcp.logs"'
    assert_includes engine, "RecordingStudioMcp::LogsRegistration.register!"
    refute_includes gemspec, '"~> 0.7"'
    assert_includes dummy_metrics, "RecordingStudioMetrics::Api.register!(api: :operations)"

    readme = File.read(File.expand_path("../README.md", __dir__))
    refute_includes readme, "config.logs_summaries_enabled"
    refute_includes readme, "mcp/usage_counts"
    refute_includes readme, "recording_studio_mcp_usage_day_summaries"
    assert_includes readme, "retention: :indefinite"
  end
end
