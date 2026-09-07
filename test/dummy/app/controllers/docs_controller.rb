# frozen_string_literal: true

class DocsController < ApplicationController
  def install
  end

  def configuration
    render :config
  end

  def recordable_types
    RecordingStudio.validate_recordable_declarations!

    @recordable_types = RecordingStudio.recordable_declarations.values.sort_by(&:type).map do |declaration|
      normalize_recordable_declaration(declaration)
    end
  end

  def recordings_tree
    recordings = RecordingStudio::Recording.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)

    @recording_tree = recordings_by_parent_id.fetch(nil, []).map do |recording|
      build_recording_node(recording, recordings_by_parent_id)
    end
  end

  def gem_views
    prefix = "#{RecordingStudioMcp::Engine.root}/"

    @engine_views = Dir.glob(RecordingStudioMcp::Engine.root.join("app/views/recording_studio_mcp/**/*.erb").to_s)
      .sort
      .map { |path| path.delete_prefix(prefix) }
  end

  def methods
  end

  def mcp
  end

  # Dummy-only helper for local MCP testing. Issues a real Oauth Bearer and probes MCP.
  def create_mcp_test_token
    return head :not_found unless mcp_test_token_minting_allowed?

    result = mint_mcp_test_token
    if result[:ok]
      @mcp_test_token = result[:token]
      @mcp_test_probe = probe_mcp_with_token(@mcp_test_token)
      render :mcp
    else
      flash.now[:alert] = result[:error]
      render :mcp, status: :unprocessable_entity
    end
  end

  # Dummy-only: prove the minted Bearer through the same post-auth MCP path as HTTP POST.
  def create_mcp_sample_post
    return head :not_found unless mcp_test_token_minting_allowed?

    token = params[:test_token].to_s
    unless token.start_with?("rsoauth_at_")
      flash.now[:alert] = "Need a test token first. Click Try MCP."
      render :mcp, status: :unprocessable_entity
      return
    end

    @mcp_test_token = token
    @mcp_sample_post = sample_post_mcp(token)
    render :mcp
  end

  private

  def mcp_test_token_minting_allowed?
    Rails.env.local?
  end
  helper_method :mcp_test_token_minting_allowed?

  def mint_mcp_test_token
    oauth_client = RecordingStudioOauth::OauthClient.find_by(name: "Seed MCP App")
    return { ok: false, error: "Seed MCP App is missing. Run seeds, then try again." } if oauth_client.nil?

    studio = Workspace.find_by(name: "Studio Workspace")
    return { ok: false, error: "Studio Workspace is missing. Run seeds, then try again." } if studio.nil?

    studio_root = RecordingStudio.root_recording_for(studio)
    access_recording = RecordingStudioAccessible.access_recordings_for_actor(
      recording: studio_root,
      actor: current_user
    ).first
    if access_recording.nil?
      return { ok: false, error: "You don’t have access to Studio Workspace. Ask someone to invite you, or run seeds." }
    end

    redirect_uri = oauth_client.redirect_uris.first
    return { ok: false, error: "Seed MCP App has no redirect URI. Fix seeds and try again." } if redirect_uri.blank?

    verifier = "V#{SecureRandom.urlsafe_base64(32)}".ljust(43, "a")
    challenge = RecordingStudioOauth::Pkce.s256_challenge(verifier)

    approved = RecordingStudioOauth::Services::CreateOauthAuthorization.call(
      oauth_client: oauth_client,
      manager_actor: current_user,
      access_recording: access_recording,
      role: "view",
      redirect_uri: redirect_uri,
      code_challenge: challenge,
      code_challenge_method: "S256"
    )
    return { ok: false, error: "Couldn’t connect Seed MCP App. Try again." } unless approved.success?

    token_result = RecordingStudioOauth::Services::IssueDelegatedAccessToken.call(
      grant_type: "authorization_code",
      client_id: oauth_client.client_id,
      code: approved.value.fetch(:code),
      redirect_uri: redirect_uri,
      code_verifier: verifier,
      api: "public"
    )
    return { ok: false, error: "Couldn’t make a test token. Try again." } unless token_result.success?

    token = token_result.value.fetch(:access_token)
    return { ok: false, error: "Couldn’t make a test token. Try again." } unless token.to_s.start_with?("rsoauth_at_")

    { ok: true, token: token }
  rescue StandardError
    { ok: false, error: "Something went wrong making a test token. Try again." }
  end

  def probe_mcp_with_token(token)
    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    return { ok: false, error: "That token didn’t authorize. Try again." } unless grant.success?

    access_grant = grant.value

    init = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => {
          "protocolVersion" => "2025-06-18",
          "capabilities" => {},
          "clientInfo" => { "name" => "dummy-test-token", "version" => "1.0" }
        }
      },
      access_grant: access_grant
    )
    return { ok: false, error: "MCP initialize failed. Check the endpoint and try again." } unless init.status == :ok

    tools = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: access_grant
    )
    return { ok: false, error: "MCP tools/list failed. Try again." } unless tools.status == :ok

    tools_body = tools.body.deep_stringify_keys
    tool_names = Array(tools_body.dig("result", "tools")).filter_map { |entry| entry["name"] }

    listed = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => { "name" => "list", "arguments" => { "type" => "Workspace" } }
      },
      access_grant: access_grant
    )
    return { ok: false, error: "MCP list workspaces failed. Try again." } unless listed.status == :ok

    listed_body = listed.body.deep_stringify_keys
    records = listed_body.dig("result", "structuredContent", "records")
    if records.blank?
      text = listed_body.dig("result", "content", 0, "text")
      records = text.present? ? JSON.parse(text).fetch("records", []) : []
    end
    workspace_names = Array(records).filter_map { |record| record["name"] }

    init_body = init.body.deep_stringify_keys
    {
      ok: true,
      server_version: init_body.dig("result", "serverInfo", "version"),
      tool_names: tool_names,
      workspace_names: workspace_names
    }
  rescue StandardError
    { ok: false, error: "MCP probe failed. Try again." }
  end

  def sample_post_mcp(token)
    # Do not nest ActionDispatch::Integration::Session here: a full inner request
    # resets ActiveSupport::CurrentAttributes and breaks page nav on render.
    grant = RecordingStudioApi.access_grant_from_authorization_header(
      authorization_header: "Bearer #{token}",
      api: "public"
    )
    return { ok: false, error: "That token didn’t authorize. Try again." } unless grant.success?

    access_grant = grant.value

    init = RecordingStudioMcp::Protocol.handle(
      {
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => {
          "protocolVersion" => "2025-06-18",
          "capabilities" => {},
          "clientInfo" => { "name" => "dummy-sample-post", "version" => "1.0" }
        }
      },
      access_grant: access_grant
    )
    return { ok: false, error: "Sample POST initialize failed. Try again." } unless init.status == :ok

    tools = RecordingStudioMcp::Protocol.handle(
      { "jsonrpc" => "2.0", "id" => 2, "method" => "tools/list" },
      access_grant: access_grant
    )
    return { ok: false, error: "Sample POST tools/list failed. Try again." } unless tools.status == :ok

    init_body = init.body.deep_stringify_keys
    tools_body = tools.body.deep_stringify_keys
    tool_names = Array(tools_body.dig("result", "tools")).filter_map { |entry| entry["name"] }

    {
      ok: true,
      status: 200,
      grant_resolved: true,
      server_version: init_body.dig("result", "serverInfo", "version"),
      tool_names: tool_names
    }
  rescue StandardError
    { ok: false, error: "Sample POST failed. Try again." }
  end

  def normalize_recordable_declaration(declaration)
    {
      name: declaration.type,
      label: declaration.label,
      root: declaration.root?,
      allowed_parent_types: RecordingStudio.allowed_parent_types_for(declaration.type),
      recordings_count: RecordingStudio::Recording.where(recordable_type: declaration.type).count,
      recordables_count: count_recordables_for(declaration.type)
    }
  end

  def count_recordables_for(type_name)
    recordable_class = type_name.safe_constantize
    return 0 unless recordable_class&.<= ActiveRecord::Base
    return 0 unless recordable_class.table_exists?

    recordable_class.count
  rescue ActiveRecord::ActiveRecordError
    0
  end

  def build_recording_node(recording, recordings_by_parent_id)
    {
      label: recording_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_recording_node(child_recording, recordings_by_parent_id)
      end
    }
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)

    "#{type_label}: #{identifier}"
  end

  def recordable_identifier(recordable)
    return "Unknown recordable" if recordable.nil?

    %i[name title email label slug identifier].each do |attribute|
      next unless recordable.respond_to?(attribute)

      value = recordable.public_send(attribute)
      return value if value.present?
    end

    actor = recordable.actor if recordable.respond_to?(:actor)
    actor_email = actor.email if actor&.respond_to?(:email) && actor.email.present?

    if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
      return "#{recordable.role.to_s.humanize} for #{actor_email}"
    end

    return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end
end
