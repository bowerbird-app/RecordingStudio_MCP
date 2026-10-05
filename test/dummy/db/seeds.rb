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

usage_subjects = %w[list show describe].freeze

usage_sample_days = lambda do
  period = RecordingStudioAdmin::Period.from_preset_key(:last_4_weeks)
  (period.start_date..period.end_date).to_a
end

write_usage_call = lambda do |stamp, index, client|
  subject = index.even? ? usage_subjects[index % 3] : "desk-notes"
  method_name = index.even? ? "tools/call" : "skills/get"
  RecordingStudioMcp::UsageLog.create!(
    occurred_at: stamp + index.minutes, method_name: method_name, subject_name: subject,
    status_code: 200, duration_ms: 8 + index, rate_limited: false, failed: false,
    api_client_id: client.id
  )
end

write_failed_usage = lambda do |stamp|
  RecordingStudioMcp::UsageLog.create!(
    occurred_at: stamp + 20.minutes, method_name: "ping", subject_name: "",
    status_code: 401, duration_ms: 3, rate_limited: false, failed: true
  )
end

write_usage_day = lambda do |day, client|
  stamp = day.in_time_zone.change(hour: 9)
  (1 + (day.yday % 4)).times { |index| write_usage_call.call(stamp, index, client) }
  write_failed_usage.call(stamp) if day.day.odd?
end

seed_mcp_usage = lambda do |client|
  next unless RecordingStudioMcp::UsageLog.table_available?

  RecordingStudioMcp::UsageLog.delete_all
  RecordingStudioMcp::UsageDailyMetric.delete_all
  usage_sample_days.call.each do |day|
    write_usage_day.call(day, client)
    RecordingStudioMcp::AggregateUsage.call(metric_date: day)
  end
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
    role: role.to_s,
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

seed_mcp_usage.call(oauth_client)

puts "Seeded: admin@admin.com / Password"
puts "Seeded: Seed MCP App client_id=#{oauth_client.client_id}"
puts "Seeded: Studio Workspace (Connected), Docs Workspace (Reconnect)"
puts "Seeded: MCP at /recording_studio_mcp"
puts "Seeded: MCP usage for the last 4 weeks"
