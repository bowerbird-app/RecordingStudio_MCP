# frozen_string_literal: true

require "test_helper"

class CatalogTest < Minitest::Test
  include RecordableMetricToolHelpers

  FakeClient = Struct.new(:api_key)
  FakeGrant = Struct.new(:api_client)

  def test_api_from_grant_uses_oauth_client_named_api
    grant = FakeGrant.new(FakeClient.new("public"))

    assert_equal "public", RecordingStudioMcp::Catalog.api_from(grant)
  end

  def test_registered_endpoints_delegates_to_the_named_api_registry
    with_isolated_api_configuration do
      RecordingStudioApi.register_endpoint(
        :ping,
        http_verb: :get,
        path: "ping",
        handler: ->(_context) { { ok: true } }
      )
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal ["ping"], catalog.registered_endpoints.map(&:name)
    end
  end

  def test_type_names_follow_the_named_api_registry
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      register_tree_type("Page")
      register_tree_type(
        "SupportPage",
        api: :operations,
        operations: %i[index show create update destroy]
      )

      public_catalog = RecordingStudioMcp::Catalog.new(api: :public)
      ops_catalog = RecordingStudioMcp::Catalog.new(api: :operations)

      assert_includes public_catalog.type_names, "Page"
      refute_includes public_catalog.type_names, "SupportPage"
      assert_includes public_catalog.type_schema.fetch(:enum), "Page"
      refute_includes public_catalog.type_schema.fetch(:enum), "SupportPage"
      assert_empty public_catalog.destroy_type_names
      assert_equal %i[create index show update], public_catalog.registered_operations.sort
      assert_equal false, public_catalog.capability_actions?

      assert_includes ops_catalog.type_names, "SupportPage"
      refute_includes ops_catalog.type_names, "Page"
      assert_includes ops_catalog.type_schema.fetch(:enum), "SupportPage"
      assert_equal ["SupportPage"], ops_catalog.destroy_type_names
      assert_includes ops_catalog.registered_operations, :destroy
      assert_equal false, ops_catalog.capability_actions?
    end
  end

  def test_registered_operations_are_the_union_across_types
    with_isolated_api_configuration do
      register_tree_type("SupportPage", operations: %i[index show])
      register_tree_type("Page", operations: %i[index show create update])
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal %i[create index show update], catalog.registered_operations.sort
      assert_equal false, catalog.capability_actions?
    end
  end

  def test_capability_actions_when_a_type_enables_them
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Workspace", capability_actions: %i[ping])
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal true, catalog.capability_actions?
      assert_equal [{ "name" => "ping" }], catalog.describe("Workspace").fetch("capability_actions")

      RecordingStudio.stub(:capability_enabled?, false) do
        assert_equal true, catalog.capability_actions?
        assert_equal [{ "name" => "ping" }], catalog.describe("Workspace").fetch("capability_actions")
      end
    end
  end

  def test_listed_actions_stay_off_tools_when_the_api_has_not_enabled_them
    with_isolated_api_configuration do
      register_tree_type("Workspace", capability_actions: %i[ping])
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal false, catalog.capability_actions?
      assert_equal [], catalog.describe("Workspace").fetch("capability_actions")
    end
  end

  def test_describe_does_not_list_metrics
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_folder_and_page_metrics
        described = RecordingStudioMcp::Catalog.new(api: :public).describe(RecordableMetricToolHelpers::FOLDER)

        expected = %w[
          type operations writable_fields capability_actions output_keys fields relationships allowed_children
        ]
        assert_equal expected, described.keys - ["parent"]
        refute described.key?("metrics")
        assert_equal RecordableMetricToolHelpers::FOLDER, described.fetch("type")
        refute_includes described.fetch("operations"), "metrics"
        assert_equal ["name"], described.fetch("output_keys")
        assert_equal [], described.fetch("fields")
        assert_equal [], described.fetch("relationships")
        assert_equal [], described.fetch("allowed_children")
      end
    end
  end

  def test_resolve_type_accepts_unambiguous_short_label
    with_isolated_api_configuration do
      register_tree_type("RecordingStudioPresskits::PressKit")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal "RecordingStudioPresskits::PressKit", catalog.resolve_type!("PressKit")
      assert_equal "RecordingStudioPresskits::PressKit",
                   catalog.resolve_type!("RecordingStudioPresskits::PressKit")
    end
  end

  def test_resolve_type_accepts_resource_name_on_a_named_api
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      register_tree_type("RecordingStudioPresskits::PressKit", api: :operations)
      catalog = RecordingStudioMcp::Catalog.new(api: :operations)

      assert_equal "RecordingStudioPresskits::PressKit", catalog.resolve_type!("press_kits")
    end
  end

  def test_resolve_type_rejects_ambiguous_short_label
    with_isolated_api_configuration do
      register_tree_type("Alpha::Page")
      register_tree_type("Beta::Page")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      error = assert_raises(RecordingStudioApi::InvalidActionInputError) { catalog.resolve_type!("Page") }

      assert_includes error.message, "matches more than one registered type"
      assert_includes error.message, "Alpha::Page"
      assert_includes error.message, "Beta::Page"
    end
  end

  def test_resolve_type_prefers_an_exact_registered_name
    with_isolated_api_configuration do
      register_tree_type("Page")
      register_tree_type("Nested::Page")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      assert_equal "Page", catalog.resolve_type!("Page")
    end
  end

  def test_describe_includes_relationships_fields_and_allowed_children
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Folder",
        serializer: ->(*) { { name: "Notes" } },
        output_keys: %i[name],
        writable_attributes: %i[name],
        operations: %i[index show],
        fields: {
          headline: { resolver: ->(*) { "Hi" }, include: true }
        },
        relationships: {
          pages: {
            source: :children,
            child_type: "Page",
            many: true,
            limit: 20,
            serializer: ->(*) { { title: "Title" } },
            output_keys: %i[title],
            description: "Pages in this folder"
          }
        }
      )
      register_tree_type("Page")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)
      parents = lambda { |type|
        type.to_s == "Page" ? ["Folder"] : []
      }

      described = RecordingStudio.stub(:allowed_parent_types_for, parents) { catalog.describe("Folder") }
      relationship = described.fetch("relationships").find { |entry| entry["name"] == "pages" }

      assert_equal ["name"], described.fetch("output_keys")
      assert_equal ["headline"], described.fetch("fields")
      assert_equal "children", relationship.fetch("source")
      assert_equal "Page", relationship.fetch("child_type")
      assert_equal true, relationship.fetch("many")
      assert_equal ["title"], relationship.fetch("output_keys")
      assert_equal "Pages in this folder", relationship.fetch("description")
      assert_includes described.fetch("allowed_children"), "Page"
      refute described.key?("metrics")
    end
  end

  def test_describe_payload_hook_can_override_the_hash
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        seen = nil
        RecordingStudioMcp.configuration.describe_payload = lambda { |payload, type:, registration:, access_grant:|
          seen = {
            type: type,
            registration: registration,
            access_grant: access_grant,
            operations: payload["operations"]
          }
          payload.merge("hint" => "list sections with parent_id")
        }
        grant = FakeGrant.new(FakeClient.new("public"))
        described = RecordingStudioMcp::Catalog.new(api: :public, access_grant: grant).describe("Page")

        assert_equal "list sections with parent_id", described.fetch("hint")
        assert described.key?("operations")
        assert_equal "Page", seen.fetch(:type)
        assert_equal "Page", seen.fetch(:registration).recordable_type
        assert_same grant, seen.fetch(:access_grant)
      end
    end
  end

  def test_unknown_type_message_names_the_allowed_set
    catalog = RecordingStudioMcp::Catalog.new(api: :public)
    names = catalog.type_names
    message = catalog.unknown_type_message("Nope")

    assert_includes message, "Unknown type Nope"
    if names.any?
      assert_includes message, "Allowed types:"
      names.each { |type| assert_includes message, type }
    else
      assert_includes message, "Allowed types: (none)"
    end
  end
end
