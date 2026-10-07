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

  def create_admin_root_recording(name: "Admin")
    admin_root = AdminRoot.find_or_create_by!(name: name)
    [admin_root, RecordingStudio.root_recording_for(admin_root)]
  end

  def grant_or_bootstrap_access!(recording:, actor:, role:)
    existing = RecordingStudioAccessible.access_recordings_for_actor(
      recording: recording,
      actor: actor
    ).first
    return existing if existing.present? && existing.recordable.role.to_s == role.to_s

    if role.to_s == "admin"
      bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: recording,
        actor: actor
      )
      return bootstrap.value if bootstrap.success?
    end

    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role.to_s,
      manager_actor: actor
    )
    return result.value if result.success?

    seed_owner = User.find_by(email: "admin@admin.com")
    if seed_owner && seed_owner != actor
      result = RecordingStudioAccessible.grant_access(
        recording: recording,
        actor: actor,
        role: role.to_s,
        manager_actor: seed_owner
      )
      return result.value if result.success?
    end

    raise result.error
  end

  def create_access_recording_for(user:, workspace_name: "Workspace #{SecureRandom.hex(4)}", role: :admin)
    Current.actor = user
    workspace = Workspace.create!(name: workspace_name)
    root_recording = RecordingStudio.root_recording_for(workspace)
    access_recording = if role.to_s == "admin"
                         grant_or_bootstrap_access!(
                           recording: root_recording,
                           actor: user,
                           role: :admin
                         )
                       else
                         grant_view_or_edit_on_new_workspace!(
                           recording: root_recording,
                           actor: user,
                           role: role
                         )
                       end

    [root_recording, access_recording]
  end

  def grant_view_or_edit_on_new_workspace!(recording:, actor:, role:)
    owner = create_user(email: "workspace-owner-#{SecureRandom.hex(4)}@example.com")
    grant_or_bootstrap_access!(recording: recording, actor: owner, role: :admin)
    Current.actor = owner
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: owner
    )
    raise result.error unless result.success?

    result.value
  end

  def create_oauth_client(name: "Demo App", confidential: false, redirect_uris: ["http://127.0.0.1/callback"], api: "public", use_central_relay: false, allowed_return_patterns: [], exact_return_urls: [], allow_registration: false, session_token_provider: nil, session_token_audience: nil, session_token_secret: nil)
    attrs = {
      name: name,
      confidential: confidential,
      redirect_uris: redirect_uris,
      api_key: api.to_s,
      use_central_relay: use_central_relay,
      allowed_return_patterns: allowed_return_patterns,
      exact_return_urls: exact_return_urls,
      allow_registration: allow_registration,
      session_token_provider: session_token_provider,
      session_token_audience: session_token_audience,
      session_token_secret: session_token_secret
    }
    secret_token = nil
    if confidential
      secret = RecordingStudioOauth::OauthClientSecret.generate
      attrs[:client_secret_digest] = secret.fetch(:digest)
      secret_token = secret.fetch(:token)
    end

    [RecordingStudioOauth::OauthClient.create!(attrs), secret_token]
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

  def named_authorize_path(api)
    "/recording_studio_oauth/apis/#{api}/oauth/authorize"
  end

  def named_api_token_path(api)
    "/recording_studio_api/apis/#{api}/oauth/token"
  end

  def named_mcp_path(api)
    "/recording_studio_mcp/apis/#{api}"
  end

  def switch_to_root!(root_recording)
    patch recording_studio_root_switchable.root_switch_path(scope: "all_workspaces"), params: {
      root_switch: {
        root_recording_id: root_recording.id,
        return_to: "/"
      }
    }
    follow_redirect! if response.redirect?
  end
end
