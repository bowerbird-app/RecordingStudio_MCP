# frozen_string_literal: true

module RecordingStudioMcp
  module UsageLogging
    extend ActiveSupport::Concern

    included do
      prepend_around_action :record_mcp_usage
    end

    private

    def record_mcp_usage
      @mcp_usage_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      record_finished_call(@mcp_usage_started) if request.post? && !@mcp_stream
    end

    def record_finished_call(started)
      UsageRecorder.record!(usage_call(started))
    end

    def record_stream_usage(payload, api_client_id, result, disconnected: false)
      return if @mcp_stream_usage_recorded

      @mcp_stream_usage_recorded = true
      started = @mcp_usage_started || Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = stream_usage_body(result, disconnected: disconnected)
      UsageRecorder.record!(
        UsageCall.new(
          request_payload: payload,
          response_body: body,
          status: 200,
          duration_ms: elapsed_milliseconds(started),
          rate_limited: rate_limited_call?,
          api_client_id: api_client_id
        )
      )
    end

    def stream_usage_body(result, disconnected:)
      return { "error" => { "code" => "disconnected" } } if disconnected
      return { "error" => { "code" => "internal_error" } } if result.nil?

      parsed = result.body
      return {} unless parsed.is_a?(Hash)

      JSON.parse(JSON.generate(parsed))
    rescue JSON::GeneratorError, TypeError, JSON::ParserError
      {}
    end

    def usage_call(started)
      UsageCall.new(
        request_payload: jsonrpc_payload,
        response_body: parsed_response_body,
        status: response.status,
        duration_ms: elapsed_milliseconds(started),
        rate_limited: rate_limited_call?,
        api_client_id: current_api_client&.id
      )
    end

    def elapsed_milliseconds(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end

    def rate_limited_call?
      @rate_limited_request == true
    end

    def parsed_response_body
      parsed = JSON.parse(response.body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError, TypeError
      {}
    end
  end
end
