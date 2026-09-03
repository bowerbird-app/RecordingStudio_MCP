# frozen_string_literal: true

find_or_record_child = lambda do |recordable, root_recording, parent_recording|
  RecordingStudio::Recording.find_by(
    root_recording: root_recording,
    parent_recording: parent_recording,
    recordable: recordable,
    trashed_at: nil
  ) || RecordingStudio.record!(
    action: "created",
    recordable: recordable,
    root_recording: root_recording,
    parent_recording: parent_recording
  ).recording
end

grant_or_find_access = lambda do |recording, actor, role|
  existing = RecordingStudioAccessible.access_recordings_for_actor(
    recording: recording,
    actor: actor
  ).first
  return existing if existing.present?

  result = RecordingStudioAccessible.grant_access(
    recording: recording,
    actor: actor,
    role: role,
    manager_actor: actor
  )
  return result.value if result.success?

  bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
    recording: recording,
    actor: actor
  )
  raise bootstrap.error if bootstrap.failure?

  bootstrap.value
end

user = User.find_or_create_by!(email: "admin@admin.com") do |u|
  u.password = "Password"
  u.password_confirmation = "Password"
end

studio = Workspace.find_or_create_by!(name: "Studio Workspace")
docs = Workspace.find_or_create_by!(name: "Docs Workspace")
folder = Folder.find_or_create_by!(name: "Product Docs")
page = Page.find_or_create_by!(title: "Getting Started")
admin_root = AdminRoot.find_or_create_by!(name: "Admin")

oauth_client = RecordingStudioOauth::OauthClient.find_or_initialize_by(name: "Seed MCP App")
oauth_client.redirect_uris = ["http://127.0.0.1:3000/callback"]
oauth_client.confidential = false
oauth_client.api_key = "public"
oauth_client.save!

previous_actor = Current.actor
Current.actor = user

begin
  studio_root = RecordingStudio.root_recording_for(studio)
  docs_root = RecordingStudio.root_recording_for(docs)
  admin_recording = RecordingStudio.root_recording_for(admin_root)
  folder_recording = find_or_record_child.call(folder, studio_root, studio_root)
  find_or_record_child.call(page, studio_root, folder_recording)

  studio_access = grant_or_find_access.call(studio_root, user, :admin)
  docs_access = grant_or_find_access.call(docs_root, user, :admin)
  grant_or_find_access.call(folder_recording, user, :edit)
  grant_or_find_access.call(admin_recording, user, :admin)

  unless RecordingStudioSiteSettings.name_for(studio_root) == "Studio"
    RecordingStudioSiteSettings.update!(studio_root, name: "Studio", actor: user)
  end
  unless RecordingStudioSiteSettings.name_for(docs_root) == "Studio"
    RecordingStudioSiteSettings.update!(docs_root, name: "Studio", actor: user)
  end

  pkce_challenge = RecordingStudioOauth::Pkce.s256_challenge("V" + ("a" * 42))

  unless RecordingStudioOauth::OauthAuthorization.exists?(oauth_client: oauth_client, manager_actor: user, manager_access_recording: studio_access, revoked_at: nil)
    connected = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: oauth_client,
      manager_actor: user,
      access_recording: studio_access,
      role: "view",
      redirect_uri: oauth_client.redirect_uris.first,
      code_challenge: pkce_challenge,
      code_challenge_method: "S256"
    )
    raise connected.error if connected.failure?
  end

  reconnect = RecordingStudioOauth::OauthAuthorization.find_by(
    oauth_client: oauth_client,
    manager_actor: user,
    manager_access_recording: docs_access
  )
  if reconnect.nil?
    created = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: oauth_client,
      manager_actor: user,
      access_recording: docs_access,
      role: "view",
      redirect_uri: oauth_client.redirect_uris.first,
      code_challenge: pkce_challenge,
      code_challenge_method: "S256"
    )
    raise created.error if created.failure?

    RecordingStudioOauth::Services::VoidOauthAuthorization.call(
      authorization: created.value.fetch(:authorization)
    )
  elsif reconnect.revoked_at.nil?
    RecordingStudioOauth::Services::VoidOauthAuthorization.call(authorization: reconnect)
  end
ensure
  Current.actor = previous_actor
end

puts "Seeded: admin@admin.com / Password"
puts "Seeded: Seed MCP App client_id=#{oauth_client.client_id}"
puts "Seeded: Studio Workspace (Connected), Docs Workspace (Reconnect)"
puts "Seeded: MCP at /recording_studio_mcp"
