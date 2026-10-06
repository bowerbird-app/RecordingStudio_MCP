# frozen_string_literal: true

require "net/http"
require "openssl"

module RecordingStudioMcp
  module CallbackHttp
    TIMEOUT = 10
    Redirected = Class.new(CallbackUrl::Error)

    module_function

    def post(url, body:, headers:)
      parsed = CallbackUrl.resolve!(url)
      request_to(parsed, body: body, headers: headers)
    end

    def request_to(parsed, body:, headers:)
      uri = parsed.uri
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = parsed.addresses.first
      http.hostname = uri.host if http.respond_to?(:hostname=)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.write_timeout = TIMEOUT if http.respond_to?(:write_timeout=)
      http.max_retries = 0

      request = Net::HTTP::Post.new(uri.request_uri)
      headers.each { |name, value| request[name] = value.to_s }
      request.body = body
      response = http.request(request)
      raise Redirected.new(:redirect, "callback redirected") if response.is_a?(Net::HTTPRedirection)

      response
    end
  end
end
