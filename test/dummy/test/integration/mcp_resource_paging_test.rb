# frozen_string_literal: true

require "base64"
require "json"
require "test_helper"

class McpResourcePagingTest < ActiveSupport::TestCase
  include OauthDummyHelpers

  setup do
    @previous_page_size = RecordingStudioMcp.configuration.resources_page_size
    RecordingStudioMcp.configuration.resources_page_size = 2
    @owner = create_user
    @viewer = create_user(email: "viewer-#{SecureRandom.hex(4)}@example.com")
    @root, @owner_access = create_access_recording_for(user: @owner, workspace_name: "Paging #{SecureRandom.hex(4)}")
    Current.actor = @owner
    @folder = @root.record(Folder, actor: @owner) { |folder| folder.name = "Notes" }
    @inside = @root.record(Page, actor: @owner, parent_recording: @folder) { |page| page.title = "Inside" }
    @sibling = @root.record(Page, actor: @owner) { |page| page.title = "Sibling" }
    @folder_access = grant_on(@folder, @viewer)
    outsider = create_user(email: "outsider-#{SecureRandom.hex(4)}@example.com")
    foreign_root, = create_access_recording_for(user: outsider, workspace_name: "Foreign #{SecureRandom.hex(4)}")
    Current.actor = outsider
    @foreign = foreign_root.record(Page, actor: outsider) { |page| page.title = "Foreign" }
  end

  teardown do
    RecordingStudioMcp.configuration.resources_page_size = @previous_page_size
    Current.actor = nil if defined?(Current)
  end

  test "paging a root grant returns each accessible recording once" do
    grant = access_grant(@owner_access)
    pages = each_page(grant)
    collected = pages.flat_map { |page| recording_ids(page) }
    expected = grant.accessible_recordings.reorder(id: :asc).pluck(:id)

    assert_equal expected, collected
    assert_equal expected.uniq, collected
    assert_operator pages.size, :>, 1
    assert_nil pages.last[:nextCursor]
    assert pages[0...-1].all? { |page| page[:nextCursor].present? }
    refute_includes collected, @foreign.id
  end

  test "a forged cursor cannot reveal recordings outside the grant" do
    grant = access_grant(@owner_access)
    pages = each_page(grant, cursor: cursor_for(@foreign.id))
    collected = pages.flat_map { |page| recording_ids(page) }
    expected = grant.accessible_recordings.where(id_after(@foreign.id)).reorder(id: :asc).pluck(:id)

    assert_equal expected, collected
    refute_includes collected, @foreign.id
    assert_nil pages.last[:nextCursor]
  end

  test "a subtree grant lists only its subtree" do
    grant = access_grant(@folder_access)
    owner = access_grant(@owner_access)
    pages = each_page(grant)
    collected = pages.flat_map { |page| recording_ids(page) }
    expected = grant.accessible_recordings.reorder(id: :asc).pluck(:id)

    assert_includes owner.accessible_recordings.pluck(:id), @sibling.id
    assert_includes expected, @inside.id
    assert_includes expected, @folder.id
    refute_includes expected, @sibling.id
    refute_includes expected, @root.id
    refute_includes expected, @foreign.id
    assert_equal expected, collected

    forged = each_page(grant, cursor: cursor_for(@sibling.id))
    forged_ids = forged.flat_map { |page| recording_ids(page) }
    assert_equal grant.accessible_recordings.where(id_after(@sibling.id)).reorder(id: :asc).pluck(:id), forged_ids
    refute_includes forged_ids, @sibling.id
    refute_includes forged_ids, @foreign.id

    inside = RecordingStudioMcp::Resources.read(access_grant: grant, uri: "recording://#{@inside.id}")
    sibling = RecordingStudioMcp::Resources.read(access_grant: grant, uri: "recording://#{@sibling.id}")
    assert_instance_of RecordingStudioMcp::Resources::Read, inside
    assert_instance_of RecordingStudioMcp::Resources::NotFound, sibling
  end

  test "a malformed cursor is invalid params and the page query stays limited" do
    grant = access_grant(@owner_access)
    answer = RecordingStudioMcp::Resources.list(access_grant: grant, cursor: "' OR 1=1 --")
    assert_instance_of RecordingStudioMcp::Resources::InvalidParams, answer

    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      RecordingStudioMcp::Resources.list(access_grant: grant)
    end

    recording_selects = queries.select { |sql| sql.include?("recording_studio_recordings") && sql.match?(/\ASELECT/i) }
    assert recording_selects.any? { |sql| sql.match?(/\bLIMIT\b/i) }
  end

  private

  def grant_on(recording, actor)
    Current.actor = @owner
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: "view",
      manager_actor: @owner
    )
    raise result.error unless result.success?

    result.value
  end

  def access_grant(access_recording)
    RecordingStudioApi::AccessGrant.new(
      api_client: nil,
      credential: nil,
      access_recording: access_recording,
      root_recording: @root
    )
  end

  def each_page(grant, cursor: nil)
    seen = []
    pages = []
    loop do
      answer = RecordingStudioMcp::Resources.list(access_grant: grant, cursor: cursor)
      assert_instance_of RecordingStudioMcp::Resources::List, answer
      pages << answer.payload
      cursor = answer.payload[:nextCursor]
      break if cursor.nil?
      flunk "repeated cursor" if seen.include?(cursor)

      seen << cursor
    end
    pages
  end

  def recording_ids(payload)
    payload[:resources].filter_map do |entry|
      uri = entry[:uri].to_s
      uri.delete_prefix("recording://") if uri.start_with?("recording://")
    end
  end

  def cursor_for(id)
    Base64.strict_encode64(JSON.generate("id" => id))
  end

  def id_after(id)
    RecordingStudio::Recording.arel_table[:id].gt(id)
  end
end
