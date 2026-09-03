# frozen_string_literal: true

require "test_helper"

class AuthenticatorTest < Minitest::Test
  FakeResult = Struct.new(:failure?, :value, keyword_init: true)
  FakeClient = Struct.new(:api_key)
  FakeCredential = Struct.new(:api_client)

  def test_blank_header_is_missing_token
    result = RecordingStudioMcp::Authenticator.access_grant("")

    refute result.success?
    assert_equal :missing_token, result.error
  end

  def test_non_bearer_scheme_is_missing_token
    result = RecordingStudioMcp::Authenticator.access_grant("Basic abc")

    refute result.success?
    assert_equal :missing_token, result.error
  end

  def test_invalid_api_grant_is_invalid_token
    RecordingStudioApi.stub(:token_authenticators, []) do
      RecordingStudioApi.stub(:access_grant_from_authorization_header, lambda { |**|
        FakeResult.new(failure?: true, value: nil)
      }) do
        result = RecordingStudioMcp::Authenticator.access_grant("Bearer rsoauth_at_nope")

        refute result.success?
        assert_equal :invalid_token, result.error
      end
    end
  end

  def test_successful_grant_uses_named_api_from_token_authenticator
    credential = FakeCredential.new(FakeClient.new("public"))
    authenticator = ->(token:) { token.start_with?("rsoauth_at_") ? { credential: credential } : nil }
    grant = Object.new
    seen = nil

    RecordingStudioApi.stub(:token_authenticators, [authenticator]) do
      RecordingStudioApi.stub(
        :access_grant_from_authorization_header,
        lambda do |authorization_header:, api:|
          seen = { header: authorization_header, api: api }
          FakeResult.new(failure?: false, value: grant)
        end
      ) do
        result = RecordingStudioMcp::Authenticator.access_grant("Bearer rsoauth_at_ok")

        assert result.success?
        assert_equal grant, result.access_grant
        assert_equal "Bearer rsoauth_at_ok", seen[:header]
        assert_equal "public", seen[:api]
      end
    end
  end

  def test_unknown_token_falls_back_to_public_api
    seen_api = nil

    RecordingStudioApi.stub(:token_authenticators, []) do
      RecordingStudioApi.stub(
        :access_grant_from_authorization_header,
        lambda do |**kwargs|
          seen_api = kwargs[:api]
          FakeResult.new(failure?: false, value: Object.new)
        end
      ) do
        RecordingStudioMcp::Authenticator.access_grant("Bearer opaque")
      end
    end

    assert_equal :public, seen_api
  end
end
