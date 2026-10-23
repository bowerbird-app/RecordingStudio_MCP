# frozen_string_literal: true

module RecordingStudioMcp
  class Dispatcher
    private

    def dispatch_endpoint(endpoint, args)
      context = endpoint_context(endpoint, args)
      success_result(serialize_endpoint_result(endpoint, endpoint.handler.call(context)))
    end

    def endpoint_context(endpoint, args)
      RecordingStudioApi::RegisteredEndpointContext.new(
        api_client: access_grant.api_client,
        credential: access_grant.credential,
        access_recording: access_grant.access_recording,
        access_grant: access_grant,
        root_recording: access_grant.root_recording,
        params: endpoint_params(endpoint, args),
        progress_reporter: progress_reporter
      )
    end

    def endpoint_params(endpoint, args)
      apply_endpoint_contract(endpoint, merge_endpoint_args(endpoint, args))
    end

    def merge_endpoint_args(endpoint, args)
      path_keys = endpoint_path_keys(endpoint)
      require_endpoint_path_args!(path_keys, args)
      captures = path_keys.to_h { |key| [key.to_sym, args[key]] }
      remaining = stringify_keys(args).except(*path_keys)
      remaining = remaining.deep_symbolize_keys if remaining.respond_to?(:deep_symbolize_keys)
      remaining.merge(captures)
    end

    def endpoint_path_keys(endpoint)
      endpoint.path_segments.filter_map do |segment|
        segment.delete_prefix(":") if segment.start_with?(":")
      end
    end

    def require_endpoint_path_args!(path_keys, args)
      path_keys.each do |key|
        raise RecordingStudioApi::InvalidActionInputError, "#{key} is required" if args[key].blank?
      end
    end

    def apply_endpoint_contract(endpoint, merged)
      return merged if endpoint.input_contract.nil?

      contract_result = endpoint.input_contract.call(merged)
      return contract_result.value if contract_result.success?

      raise RecordingStudioApi::InvalidActionInputError.new(
        "Invalid input for endpoint #{endpoint.name}",
        details: contract_result.errors
      )
    end

    def serialize_endpoint_result(endpoint, result)
      serializer = endpoint.serializer
      serializer.nil? ? result : serializer.call(result)
    end
  end
end
