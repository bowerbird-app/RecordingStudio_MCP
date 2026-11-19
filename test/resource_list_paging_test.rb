# frozen_string_literal: true

require "base64"
require "json"
require "test_helper"
require "tmpdir"

class ResourceListPagingTest < Minitest::Test
  Recording = Struct.new(:id, :recordable_type, :recordable, :parent_recording_id, :root_recording_id)
  IDS = %w[
    00000000-0000-4000-8000-000000000001
    00000000-0000-4000-8000-000000000003
    00000000-0000-4000-8000-000000000005
    00000000-0000-4000-8000-000000000007
    00000000-0000-4000-8000-000000000009
  ].freeze
  OUTSIDE = %w[
    00000000-0000-4000-8000-000000000002
    00000000-0000-4000-8000-000000000004
    00000000-0000-4000-8000-000000000008
  ].freeze

  def test_paging_returns_each_accessible_recording_once
    pages = with_page_size(2) { each_page(grant_for(IDS)) }
    collected = pages.flat_map { |page| recording_ids(page) }

    assert_equal IDS, collected
    assert_equal IDS.uniq, collected
    assert_nil pages.last[:nextCursor]
    assert(pages[0...-1].all? { |page| page[:nextCursor].present? })
    assert(pages[0...-1].all? { |page| recording_ids(page).size == 2 })
    refute_includes pages.first[:nextCursor], IDS.first
  end

  def test_a_full_page_has_no_next_cursor
    pages = with_page_size(2) { each_page(grant_for(IDS.first(2))) }

    assert_equal 1, pages.size
    assert_equal IDS.first(2), recording_ids(pages.first)
    refute pages.first.key?(:nextCursor)
  end

  def test_a_forged_cursor_returns_only_later_rows_inside_the_grant
    outside = OUTSIDE[1]
    pages = with_page_size(2) { each_page(grant_for(IDS), cursor: cursor_for(outside)) }
    collected = pages.flat_map { |page| recording_ids(page) }

    assert_equal IDS.select { |id| id > outside }, collected
    refute_includes collected, outside
    OUTSIDE.each { |id| refute_includes collected, id }
    assert_nil pages.last[:nextCursor]
  end

  def test_a_subtree_grant_lists_only_that_subtree
    subtree = IDS.first(3)
    pages = with_page_size(2) { each_page(grant_for(subtree)) }
    collected = pages.flat_map { |page| recording_ids(page) }

    assert_equal subtree, collected
    (IDS - subtree + OUTSIDE).each { |id| refute_includes collected, id }

    forged = with_page_size(2) { each_page(grant_for(subtree), cursor: cursor_for(OUTSIDE.first)) }
    forged_ids = forged.flat_map { |page| recording_ids(page) }
    assert_equal subtree.select { |id| id > OUTSIDE.first }, forged_ids
    refute_includes forged_ids, OUTSIDE.first
  end

  def test_a_malformed_cursor_is_invalid_params_and_is_not_echoed
    grant = grant_for(IDS)
    cursors = [
      "next",
      "",
      "not-a-cursor",
      cursor_for("not-a-uuid"),
      cursor_for(IDS.first, extra: { "root" => IDS.first }),
      Base64.strict_encode64("[]"),
      Base64.strict_encode64(%({"id":)),
      "' OR 1=1 --",
      IDS.first,
      4,
      { "id" => IDS.first }
    ]

    cursors.each do |cursor|
      answer = RecordingStudioMcp::Resources.list(access_grant: grant, cursor: cursor)
      assert_instance_of RecordingStudioMcp::Resources::InvalidParams, answer, cursor.inspect

      result = RecordingStudioMcp::Protocol.handle(
        { "jsonrpc" => "2.0", "id" => 1, "method" => "resources/list", "params" => { "cursor" => cursor } },
        access_grant: grant
      )
      assert_equal(-32_602, result.body.dig(:error, :code))
      assert_equal "Invalid params", result.body.dig(:error, :message)
      refute result.body[:error].key?(:data)
      body = JSON.generate(result.body)
      refute_includes body, cursor.to_s if cursor.is_a?(String) && cursor.bytesize > 8
    end
  end

  def test_an_issued_cursor_and_a_whitespace_cursor_page_the_same_rows
    grant = grant_for(IDS)
    pages = with_page_size(2) { each_page(grant) }
    issued = pages.first[:nextCursor]
    again = with_page_size(2) { each_page(grant, cursor: issued) }

    loose = Base64.strict_encode64(%(\n{\n  "id" : "#{IDS[1].upcase}"\n}\n))
    from_loose = with_page_size(2) { each_page(grant, cursor: loose) }

    assert_equal recording_ids_from(again), recording_ids_from(from_loose)
    assert_equal IDS.drop(2), recording_ids_from(again)
  end

  def test_skills_are_on_the_first_page_only
    with_page_size(2) do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "SKILL.md")
        File.write(path, "---\nname: desk-notes\ndescription: Notes.\n---\nHi\n")
        RecordingStudioMcp.register_skill(name: "desk-notes", path: path)
        include_mcp_skills("desk-notes")
        ids = IDS.first(3)
        pages = each_page(grant_for(ids))

        assert_equal "skill://desk-notes/SKILL.md", pages.first[:resources].first[:uri]
        assert_equal ids.first(2), recording_ids(pages.first)
        assert_equal ids.last(1), recording_ids(pages.last)
        assert(pages.drop(1).none? { |page| page[:resources].any? { |entry| entry[:uri].start_with?("skill://") } })
        assert_nil pages.last[:nextCursor]
      end
    end
  end

  def test_modern_list_keeps_next_cursor_with_the_result_shape
    listed = with_page_size(2) do
      RecordingStudioMcp::Resources.list(access_grant: grant_for(IDS), protocol_version: "2026-07-28")
    end

    assert_equal "complete", listed.payload[:resultType]
    assert listed.payload[:nextCursor].present?
    assert_equal IDS.first(2), recording_ids(listed.payload)
  end

  private

  def grant_for(ids)
    rows = ids.map { |id| Recording.new(id, "Page", Struct.new(:title).new(id), nil, IDS.first) }
    Struct.new(:recordings) { def accessible_recordings = recordings }.new(GrantScope.new(rows))
  end

  def with_page_size(size)
    with_isolated_mcp_configuration do
      RecordingStudioMcp.configuration.resources_page_size = size
      yield
    end
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

  def recording_ids_from(pages)
    pages.flat_map { |page| recording_ids(page) }
  end

  def cursor_for(id, extra: {})
    Base64.strict_encode64(JSON.generate({ "id" => id }.merge(extra)))
  end

  class GrantScope
    def initialize(rows, lower_id: nil)
      @rows = rows
      @lower_id = lower_id
    end

    def arel_table
      Table.new
    end

    def where(lower_id)
      self.class.new(@rows, lower_id: lower_id)
    end

    def reorder(*)
      self
    end

    def limit(count)
      selected.first(count)
    end

    def find_by(id:)
      @rows.find { |row| row.id.to_s == id.to_s }
    end

    class Table
      def [](_name)
        self
      end

      def gt(id)
        id
      end
    end

    private

    def selected
      rows = @rows
      rows = rows.select { |row| row.id.to_s.downcase > @lower_id.to_s } if @lower_id
      rows.sort_by { |row| row.id.to_s.downcase }
    end
  end
end
