# frozen_string_literal: true

module RecordingStudioMcp
  module RecordableMetricTools
    module_function

    def execute(tool, arguments, access_grant)
      RecordingStudioApi::Services::ResourceMetrics::Show.call(
        operation_context(tool, arguments, access_grant)
      )
    end

    def operation_context(tool, arguments, access_grant)
      RecordingStudioApi::ResourceOperationContext.new(**metric_context(tool, arguments, access_grant))
    end

    def metric_context(tool, arguments, access_grant)
      {
        recording: nil, parent_recording: nil, idempotency_key: nil,
        recordable_type: tool.recordable_type, resource_name: tool.resource_name,
        api_client: access_grant.api_client, credential: access_grant.credential,
        access_recording: access_grant.access_recording, access_grant: access_grant,
        root_recording: access_grant.root_recording,
        api_version: RecordingStudioApi.default_api_version(api: tool.api),
        params: ActionController::Parameters.new(params_for(tool, arguments)).permit!,
        request_params: empty_request_params, scoped_recordings: access_grant.accessible_recordings
      }.merge(AuthorizedBy.context_keywords(RecordingStudioApi::ResourceOperationContext, access_grant))
    end

    def empty_request_params
      # GET carries no body. Show reads the metric query from params.
      ActionController::Parameters.new.permit!
    end
    private_class_method :operation_context, :metric_context, :empty_request_params
  end
end
