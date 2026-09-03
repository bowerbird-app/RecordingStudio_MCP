# frozen_string_literal: true

require "test_helper"

module OauthDummyHelpers
  TEST_PASSWORD = "OauthDummyPassword!2026"

  def create_user(email: "oauth-user-#{SecureRandom.hex(4)}@example.com")
    User.find_or_create_by!(email: email) do |user|
      user.password = TEST_PASSWORD
      user.password_confirmation = TEST_PASSWORD
    end
  end

  def grant_or_bootstrap_access!(recording:, actor:, role:)
    existing = RecordingStudioAccessible.access_recordings_for_actor(
      recording: recording,
      actor: actor
    ).first
    return existing if existing.present? && existing.recordable.role.to_s == role.to_s

    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: actor
    )
    return result.value if result.success?

    if role.to_s == "admin"
      bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: recording,
        actor: actor
      )
      return bootstrap.value if bootstrap.success?
    end

    create_access_without_manager!(recording: recording, actor: actor, role: role)
  end

  def create_access_without_manager!(recording:, actor:, role:)
    RecordingStudioAccessible::AccessCreationContext.allow do
      access = RecordingStudio::Access.create!(actor: actor, role: role)
      RecordingStudio.record!(
        action: "created",
        recordable: access,
        root_recording: recording.root_recording || recording,
        parent_recording: recording
      ).recording
    end
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio.root_recording_for(workspace)
    access_recording = grant_or_bootstrap_access!(
      recording: root_recording,
      actor: user,
      role: role
    )

    [root_recording, access_recording]
  end

  def create_oauth_client(name: "Demo App", confidential: false, redirect_uris: ["http://127.0.0.1/callback"], api: "public")
    attrs = {
      name: name,
      confidential: confidential,
      redirect_uris: redirect_uris,
      api_key: api.to_s
    }

    [RecordingStudioOauth::OauthClient.create!(attrs), nil]
  end

  def pkce_pair
    verifier = "V#{SecureRandom.urlsafe_base64(32)}"
    verifier = verifier.ljust(43, "a")
    {
      verifier: verifier,
      challenge: RecordingStudioOauth::Pkce.s256_challenge(verifier)
    }
  end

  def approve_delegated_oauth(oauth_client:, user:, access_recording:, role: "view", redirect_uri: "http://127.0.0.1/callback", pkce: nil)
    pkce ||= pkce_pair
    result = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: oauth_client,
      manager_actor: user,
      access_recording: access_recording,
      role: role,
      redirect_uri: redirect_uri,
      code_challenge: pkce.fetch(:challenge),
      code_challenge_method: "S256"
    )
    raise result.error unless result.success?

    result.value.merge(pkce: pkce, redirect_uri: redirect_uri)
  end
end
