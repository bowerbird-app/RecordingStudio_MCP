# frozen_string_literal: true

require "test_helper"

class RecordingStudioTemplateTest < ActiveSupport::TestCase
  test "dummy app loads root switchable config and controller support" do
    assert_equal [ "all_workspaces" ], RecordingStudioRootSwitchable.configuration.scopes.keys
    assert_includes ApplicationController.ancestors, RecordingStudio::RootSwitchable::ControllerSupport
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end

  test "dummy app validates recordable declarations" do
    assert RecordingStudio.validate_recordable_declarations!
    assert_includes RecordingStudio.root_recordable_types, "Workspace"
    assert_includes RecordingStudio.root_recordable_types, "AdminRoot"
    assert_equal [ "Workspace", "Folder" ], RecordingStudio.allowed_parent_types_for("Page")
  end

  test "dummy app schema keeps accessible grants and excludes removed core tables" do
    connection = ActiveRecord::Base.connection

    assert connection.column_exists?(:recording_studio_recordings, :root_recording_id)
    assert connection.table_exists?(:recording_studio_accesses)
    assert connection.table_exists?(:recording_studio_oauth_clients)
    refute connection.table_exists?(:recording_studio_access_boundaries)
    refute connection.table_exists?(:recording_studio_device_sessions)
  end

  test "dummy seeds use hierarchy idempotently and restore current actor" do
    Current.actor = nil

    load Rails.root.join("db/seeds.rb").to_s

    workspace = Workspace.find_by!(name: "Studio Workspace")
    folder = Folder.find_by!(name: "Product Docs")
    page = Page.find_by!(title: "Getting Started")
    root_recording = RecordingStudio::Recording.find_by!(recordable: workspace)
    folder_recording = RecordingStudio::Recording.find_by!(recordable: folder)
    page_recording = RecordingStudio::Recording.find_by!(recordable: page)
    oauth_client = RecordingStudioOauth::OauthClient.find_by!(name: "Seed MCP App")

    assert_nil Current.actor
    assert_nil root_recording.parent_recording_id
    assert_equal root_recording, folder_recording.parent_recording
    assert_equal folder_recording, page_recording.parent_recording
    assert_equal false, oauth_client.confidential
    assert_equal "public", oauth_client.api_key
    assert_equal ["http://127.0.0.1:3000/callback"], oauth_client.redirect_uris
    refute_includes oauth_client.redirect_uris.first, "#"

    assert_no_difference -> { User.count } do
      assert_no_difference -> { RecordingStudio::Recording.count } do
        load Rails.root.join("db/seeds.rb").to_s
      end
    end
    assert_nil Current.actor
  ensure
    Current.actor = nil
  end

  test "workspace opts into accessible without an example mixin" do
    workspace_source = File.read(Rails.root.join("app/models/workspace.rb"))

    refute_includes workspace_source, "Example.to"
    refute File.exist?(RecordingStudioMcp::Engine.root.join("lib/recording_studio_mcp/capabilities/example.rb"))

    assert RecordingStudio.capability_enabled?(:accessible, for: Workspace)
    refute RecordingStudio.capability_enabled?(:accessible, for: Page)
    assert_includes ApplicationController.ancestors, RecordingStudio::UsesDefaultLayout
  end

  test "dummy importmap looks up engine constants from the top-level namespace" do
    source = File.read(Rails.root.join("config/importmap.rb"))

    assert_includes source, "::RecordingStudioAdmin::Engine"
    assert_includes source, "::FlatPack::Engine"
    refute_match(/^\s*pin_all_from RecordingStudioAdmin::Engine/, source)
    refute_match(/^\s*pin_all_from FlatPack::Engine/, source)
  end
end
