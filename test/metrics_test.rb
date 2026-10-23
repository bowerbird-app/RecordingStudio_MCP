# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_metrics_register_with_operations_expose_and_admin_view
    metrics = File.read(File.expand_path("../lib/recording_studio_mcp/metrics.rb", __dir__))
    engine = File.read(File.expand_path("../lib/recording_studio_mcp/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_mcp.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))
    access = File.read(File.expand_path("../lib/recording_studio_mcp/api/access.rb", __dir__))

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

    assert_includes access, "def can_view?"
    assert_includes access, "RecordingStudioAccessible.authorized?"
    assert_includes access, "role: :view"
    assert_includes access, "access_recording_resolver"

    assert_includes engine, 'initializer "recording_studio_mcp.metrics"'
    assert_includes engine, "RecordingStudioMcp::Metrics.register!"
    refute_includes engine, "RecordingStudioMetrics::Api.register!"
    assert_includes engine, 'initializer "recording_studio_mcp.logs"'
    assert_includes engine, "RecordingStudioMcp::LogsRegistration.register!"

    assert_includes gemspec, 'spec.add_dependency "recording_studio_metrics", ">= 0.3.0", "< 1.0"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_logs", ">= 0.5.0", "< 1.0"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_api", ">= 0.16", "< 0.17"'
    refute_includes gemspec, '"~> 0.7"'
    assert_includes dummy_metrics, "RecordingStudioMetrics::Api.register!(api: :operations)"
  end

  def test_boot_registers_mcp_calls_authorize_through_api_access
    skip unless RecordingStudioMcp.const_defined?(:UsageLog, false)

    with_saved_metrics_registry do
      RecordingStudioMetrics.registry.reset!
      RecordingStudioMcp::Metrics.register!

      metric = RecordingStudioMetrics.registry.fetch("mcp_calls.over_time")
      assert_equal RecordingStudioMcp::UsageDailyMetric, metric.model
      assert_equal RecordingStudioMcp::Metrics::AUTHORIZE, RecordingStudioMetrics.registry.api_authorize_for(:mcp_calls)
      refute_nil RecordingStudioMetrics.registry.find("mcp_subscriptions.failing")

      context = Object.new
      hook = RecordingStudioMetrics.registry.api_authorize_for(:mcp_calls)
      RecordingStudioMcp::Api::Access.stub(:can_view?, true) do
        assert_equal true, hook.call(context)
      end
      RecordingStudioMcp::Api::Access.stub(:can_view?, false) do
        assert_equal false, hook.call(context)
      end
    end
  end

  def test_readme_points_hosts_at_the_existing_daily_metrics_table
    readme = File.read(File.expand_path("../README.md", __dir__))
    refute_includes readme, "config.logs_summaries_enabled"
    refute_includes readme, "mcp/usage_counts"
    refute_includes readme, "recording_studio_mcp_usage_day_summaries"
    assert_includes readme, "Do not schedule `rake recording_studio_mcp:maintain_usage`"
    assert_includes readme, "recording_studio_mcp_usage_daily_metrics"
    assert_includes readme, "DailyAggregationJob"
  end

  def with_saved_metrics_registry
    registry = RecordingStudioMetrics.registry
    saved_metrics = registry.instance_variable_get(:@metrics).dup
    saved_resources = registry.instance_variable_get(:@resources).dup
    yield
  ensure
    registry.instance_variable_set(:@metrics, saved_metrics)
    registry.instance_variable_set(:@resources, saved_resources)
  end
end
