# frozen_string_literal: true

# Dummy-only helper used by bin/docs-mcp. Prints an edit-role Bearer to stdout.
# Same Oauth seed client and Studio Workspace grant as /docs/mcp, with edit so
# create, update, and capability_action appear on tools/list.

oauth_client = RecordingStudioOauth::OauthClient.find_by!(name: "Seed MCP App")
studio = Workspace.find_by!(name: "Studio Workspace")
user = User.find_by!(email: "admin@admin.com")
studio_root = RecordingStudio.root_recording_for(studio)
access_recording = RecordingStudioAccessible.access_recordings_for_actor(
  recording: studio_root,
  actor: user
).first
raise "Studio Workspace access is missing. Run db:seed." if access_recording.nil?

redirect_uri = oauth_client.redirect_uris.first
raise "Seed MCP App has no redirect URI." if redirect_uri.blank?

verifier = "V#{SecureRandom.urlsafe_base64(32)}".ljust(43, "a")
challenge = RecordingStudioOauth::Pkce.s256_challenge(verifier)

approved = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
  oauth_client: oauth_client,
  manager_actor: user,
  access_recording: access_recording,
  role: "edit",
  redirect_uri: redirect_uri,
  code_challenge: challenge,
  code_challenge_method: "S256"
)
raise approved.error.to_s unless approved.success?

token_result = RecordingStudioOauth::Services::IssueDelegatedAccessToken.call(
  grant_type: "authorization_code",
  client_id: oauth_client.client_id,
  code: approved.value.fetch(:code),
  redirect_uri: redirect_uri,
  code_verifier: verifier,
  api: "public"
)
raise token_result.error.to_s unless token_result.success?

token = token_result.value.fetch(:access_token)
raise "Unexpected token prefix." unless token.to_s.start_with?("rsoauth_at_")

$stdout.write(token)
