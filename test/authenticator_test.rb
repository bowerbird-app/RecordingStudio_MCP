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
      RecordingStudioApi.stub(:authenticate_authorization_header, lambda { |**|
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
    authenticated = authenticated_client(credential)
    seen = nil

    RecordingStudioApi.stub(:token_authenticators, [authenticator]) do
      RecordingStudioApi.stub(
        :authenticate_authorization_header,
        lambda do |authorization_header:, api:|
          seen = { header: authorization_header, api: api }
          FakeResult.new(failure?: false, value: authenticated)
        end
      ) do
        result = RecordingStudioMcp::Authenticator.access_grant("Bearer rsoauth_at_ok")

        assert result.success?
        assert_equal credential.api_client, result.access_grant.api_client
        assert_equal credential, result.access_grant.credential
        assert_equal "Bearer rsoauth_at_ok", seen[:header]
        assert_equal "public", seen[:api]
      end
    end
  end

  def test_access_grant_keeps_the_sign_in_authorized_by
    unless access_grant_accepts_authorized_by?
      skip "API #{RecordingStudioApi::VERSION} has no AccessGrant#authorized_by"
    end

    credential = FakeCredential.new(FakeClient.new("public"))
    signed_in = Struct.new(:id).new(41)
    looked_up = Struct.new(:id).new(99)
    authenticated = authenticated_client(credential, authorized_by: signed_in)
    authenticator = ->(**) { { credential: credential } }

    RecordingStudioApi.stub(:token_authenticators, [authenticator]) do
      RecordingStudioApi.stub(:authenticate_authorization_header, lambda { |**|
        FakeResult.new(failure?: false, value: authenticated)
      }) do
        RecordingStudioApi::AuthorizedBy.stub(:actor_for, looked_up) do
          result = RecordingStudioMcp::Authenticator.access_grant("Bearer rsoauth_at_ok")

          assert_equal signed_in, result.access_grant.authorized_by
        end
      end
    end
  end

  def test_unknown_token_falls_back_to_public_api
    seen_api = nil
    credential = FakeCredential.new(FakeClient.new("public"))

    RecordingStudioApi.stub(:token_authenticators, []) do
      RecordingStudioApi.stub(
        :authenticate_authorization_header,
        lambda do |**kwargs|
          seen_api = kwargs[:api]
          FakeResult.new(failure?: false, value: authenticated_client(credential))
        end
      ) do
        RecordingStudioMcp::Authenticator.access_grant("Bearer opaque")
      end
    end

    assert_equal :public, seen_api
  end

  private

  def authenticated_client(credential, authorized_by: nil)
    Struct.new(:api_client, :credential, :access_recording, :root_recording, :authorized_by).new(
      credential.api_client,
      credential,
      nil,
      nil,
      authorized_by
    )
  end

  def access_grant_accepts_authorized_by?
    RecordingStudioApi::AccessGrant.instance_method(:initialize).parameters.any? do |_type, name|
      name == :authorized_by
    end
  end
end
