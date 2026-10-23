# frozen_string_literal: true

require "test_helper"

class MetricsTest < Minitest::Test
  def test_boot_registers_mcp_calls_authorize_through_api_access
    skip unless RecordingStudioMcp.const_defined?(:UsageLog, false)

    RecordingStudioMetrics.registry.reset!
    RecordingStudioMcp::Metrics.register!

    metric = RecordingStudioMetrics.registry.fetch("mcp_calls.over_time")
    assert_equal RecordingStudioMcp::UsageLog, metric.model
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

  def test_engine_registers_metrics_and_logs_on_prepare
    engine = File.read(File.expand_path("../lib/recording_studio_mcp/engine.rb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_mcp.gemspec", __dir__))
    dummy_metrics = File.read(File.expand_path("dummy/config/initializers/recording_studio_metrics.rb", __dir__))

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

  def test_readme_does_not_point_hosts_at_summary_tables
    readme = File.read(File.expand_path("../README.md", __dir__))
    refute_includes readme, "config.logs_summaries_enabled"
    refute_includes readme, "mcp/usage_counts"
    refute_includes readme, "recording_studio_mcp_usage_day_summaries"
    assert_includes readme, "retention: :indefinite"
    refute_includes readme, "rake recording_studio_mcp:maintain_usage"
  end
end
