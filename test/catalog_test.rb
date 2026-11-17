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
      ping = catalog.describe("Workspace").fetch("capability_actions")

      assert_equal [{ "name" => "ping", "title" => "Workspace - Ping" }], ping
      refute ping.first.key?("summary")
      refute ping.first.key?("description")

      RecordingStudio.stub(:capability_enabled?, false) do
        assert_equal true, catalog.capability_actions?
        assert_equal [{ "name" => "ping", "title" => "Workspace - Ping" }],
                     catalog.describe("Workspace").fetch("capability_actions")
      end
    end
  end

  def test_describe_includes_action_title_and_summary_when_registered
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :ping,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: {
          title: "Ping Workspace",
          summary: "Ping this workspace",
          description: "A longer note about ping."
        }
      )
      register_tree_type("Workspace", capability_actions: %i[ping])
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Workspace")
      ping = described.fetch("capability_actions").first

      assert_equal "ping", ping.fetch("name")
      assert_equal "Workspace - Ping Workspace", ping.fetch("title")
      assert_equal "Ping this workspace", ping.fetch("summary")
      assert_equal "A longer note about ping.", ping.fetch("description")
    end
  end

  def test_describe_omits_blank_action_openapi_fields
    with_isolated_api_configuration do
      RecordingStudioApi.register_capability_action(
        :ping,
        capability: :accessible,
        handler: ->(_context) { { json: { ok: true } } },
        openapi: { title: "", summary: "   " }
      )
      register_tree_type("Workspace", capability_actions: %i[ping])
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Workspace")
      ping = described.fetch("capability_actions").first

      assert_equal({ "name" => "ping", "title" => "Workspace - Ping" }, ping)
    end
  end

  def test_describe_includes_type_description_when_registered
    with_isolated_api_configuration do
      register_tree_type("Workspace", openapi: { description: "A workspace root." })
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Workspace")

      assert_equal "A workspace root.", described.fetch("description")
    end
  end

  def test_describe_uses_tag_description_when_type_description_is_unset
    with_isolated_api_configuration do
      register_tree_type(
        "Workspace",
        openapi: { tag: { description: "Credits on a press kit." } }
      )
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Workspace")

      assert_equal "Credits on a press kit.", described.fetch("description")
    end
  end

  def test_describe_omits_type_description_when_unset
    with_isolated_api_configuration do
      register_tree_type("Workspace")
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Workspace")

      refute described.key?("description")
    end
  end

  def test_describe_includes_auto_enabled_capability_actions
    with_isolated_api_configuration do
      register_ping_capability
      register_tree_type("Workspace", capability_actions: %i[ping])
      ping = RecordingStudioApi.capability_action(:ping, api: :public)
      grant = Struct.new(:name, :input_contract, :openapi).new(:grant_access, nil, nil)
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      RecordingStudioApi.stub(:capability_actions_for, [ping, grant]) do
        names = catalog.describe("Workspace").fetch("capability_actions").map { |entry| entry["name"] }

        assert_equal %w[grant_access ping], names.sort
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

  def test_describe_lists_created_at_and_registered_sortable_fields
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Page",
        serializer: ->(*) { { title: "Title" } },
        output_keys: %i[title],
        operations: %i[index],
        sortable_attributes: %i[title]
      )

      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Page")

      assert_equal %w[created_at title], described.fetch("sortable_fields")
    end
  end

  def test_describe_does_not_list_metrics
    with_isolated_api_configuration do
      with_recordable_metric_registry do
        register_folder_and_page_metrics
        described = RecordingStudioMcp::Catalog.new(api: :public).describe("Folder")

        expected = %w[
          type operations writable_fields sortable_fields capability_actions output_keys fields relationships
          allowed_children
        ]
        assert_equal expected, described.keys - ["parent"]
        refute described.key?("metrics")
        assert_equal "Folder", described.fetch("type")
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
      assert_equal "PressKit", catalog.describe("PressKit").fetch("type")
      assert_includes catalog.type_schema.fetch(:enum), "PressKit"
      refute_includes catalog.type_schema.fetch(:enum), "RecordingStudioPresskits::PressKit"

      rejected = assert_raises(RecordingStudioApi::NotFoundError) do
        catalog.resolve_type!("RecordingStudioPresskits::PressKit")
      end
      assert_includes rejected.message, "Unknown type RecordingStudioPresskits::PressKit"
      assert_includes rejected.message, "Allowed types: PressKit"
      refute_includes rejected.message.split("Allowed types:").last, "RecordingStudioPresskits::PressKit"

      error = assert_raises(RecordingStudioApi::NotFoundError) { catalog.resolve_type!("MissingKit") }
      assert_includes error.message, "Allowed types: PressKit"
      refute_includes error.message, "RecordingStudioPresskits::PressKit"
    end
  end

  def test_resolve_type_accepts_a_resource_name_only_when_it_is_the_public_name
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      register_tree_type("RecordingStudioPresskits::PressKit", api: :operations)
      catalog = RecordingStudioMcp::Catalog.new(api: :operations)

      error = assert_raises(RecordingStudioApi::NotFoundError) { catalog.resolve_type!("press_kits") }
      assert_includes error.message, "Unknown type press_kits"
      assert_includes error.message, "Allowed types: PressKit"

      with_public_name("RecordingStudioPresskits::PressKit", :operations, "press_kits") do
        named = RecordingStudioMcp::Catalog.new(api: :operations)

        assert_equal "RecordingStudioPresskits::PressKit", named.resolve_type!("press_kits")
        rejected = assert_raises(RecordingStudioApi::NotFoundError) { named.resolve_type!("PressKit") }
        assert_includes rejected.message, "Allowed types: press_kits"
      end
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

  def test_resolve_type_rejects_an_unregistered_short_label
    with_isolated_api_configuration do
      register_tree_type("Folder")
      register_tree_type("Page")
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      error = assert_raises(RecordingStudioApi::NotFoundError) { catalog.resolve_type!("PressKit") }

      assert_includes error.message, "Unknown type PressKit"
      assert_includes error.message, "Allowed types:"
      assert_includes error.message, "Folder"
      assert_includes error.message, "Page"
      refute_includes error.message.split("Allowed types:").last, "PressKit"
    end
  end

  def test_resolve_type_short_label_stays_on_this_named_api
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      register_tree_type("Page")
      register_tree_type("RecordingStudioPresskits::PressKit", api: :operations)
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      error = assert_raises(RecordingStudioApi::NotFoundError) { catalog.resolve_type!("PressKit") }

      assert_includes error.message, "Unknown type PressKit"
      assert_includes error.message, "Page"
      refute_includes error.message, "RecordingStudioPresskits::PressKit"
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

  def test_describe_omits_relationships_and_children_not_on_this_api
    with_isolated_api_configuration do
      RecordingStudioApi.register_recordable_type_api(
        "Folder",
        serializer: ->(*) { { name: "Notes" } },
        output_keys: %i[name],
        writable_attributes: %i[name],
        operations: %i[index show],
        relationships: {
          pages: {
            source: :children,
            child_type: "Page",
            many: true,
            limit: 20,
            serializer: ->(*) { { title: "Title" } },
            output_keys: %i[title]
          },
          articles: {
            source: :children,
            child_type: "Article",
            many: true,
            limit: 20,
            serializer: ->(*) { { title: "Title" } },
            output_keys: %i[title]
          }
        }
      )
      register_tree_type("Page")
      described = RecordingStudioMcp::Catalog.new(api: :public).describe("Folder")
      names = described.fetch("relationships").map { |entry| entry["name"] }

      assert_equal ["pages"], names
      assert_equal ["Page"], described.fetch("allowed_children")
      refute_includes described.fetch("allowed_children"), "Article"
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

  def test_describe_payload_hook_can_replace_the_hash
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        RecordingStudioMcp.configuration.describe_payload = ->(*) { { hint: "only" } }
        described = RecordingStudioMcp::Catalog.new(api: :public).describe("Page")

        assert_equal({ "hint" => "only" }, described)
        refute described.key?("operations")
        refute described.key?("type")
      end
    end
  end

  def test_describe_payload_keeps_the_default_when_the_hook_is_not_a_hash
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        default = catalog.describe("Page")

        [nil, "nope"].each do |result|
          RecordingStudioMcp.configuration.describe_payload = ->(*) { result }
          described = catalog.describe("Page")

          assert_equal default, described
          assert described.key?("operations")
        end
      end
    end
  end

  def test_list_parent_id_is_off_until_configured
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Page")
        catalog = RecordingStudioMcp::Catalog.new(api: :public)

        assert_equal false, catalog.list_parent_id?
        assert_equal [], catalog.list_parent_id_type_names
      end
    end
  end

  def test_list_parent_id_types_are_the_configured_index_types
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Folder")
        register_tree_type("Page")
        RecordingStudioMcp.configuration.list_parent_id_types = %w[Page]
        catalog = RecordingStudioMcp::Catalog.new(api: :public)

        assert_equal true, catalog.list_parent_id?
        assert_equal ["Page"], catalog.list_parent_id_type_names
      end
    end
  end

  def test_list_parent_id_types_intersect_with_index_types
    with_isolated_mcp_configuration do
      with_isolated_api_configuration do
        register_tree_type("Folder")
        register_tree_type("Page", operations: %i[show create])
        RecordingStudioMcp.configuration.list_parent_id_types = %w[Page Folder Unknown]
        catalog = RecordingStudioMcp::Catalog.new(api: :public)

        assert_equal ["Folder"], catalog.list_parent_id_type_names
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
      catalog.type_schema.fetch(:enum).each { |type| assert_includes message, type }
    else
      assert_includes message, "Allowed types: (none)"
    end
  end

  def test_registration_public_name_is_the_only_accepted_type_input
    with_isolated_api_configuration do
      RecordingStudioApi.configuration.api(:operations)
      register_tree_type("RecordingStudioPresskits::PressKit")
      register_tree_type("Folder")
      register_tree_type("RecordingStudioPresskits::PressKit", api: :operations)
      with_public_name("RecordingStudioPresskits::PressKit", :public, "Kit") do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)
        operations = RecordingStudioMcp::Catalog.new(api: :operations)

        assert_includes catalog.type_schema.fetch(:enum), "Kit"
        assert_includes catalog.type_schema.fetch(:enum), "Folder"
        refute_includes catalog.type_schema.fetch(:enum), "PressKit"
        refute_includes catalog.type_schema.fetch(:enum), "RecordingStudioPresskits::PressKit"
        assert_equal "Kit", catalog.describe("Kit").fetch("type")
        assert_equal "RecordingStudioPresskits::PressKit", catalog.resolve_type!("Kit")
        demodulized = assert_raises(RecordingStudioApi::NotFoundError) { catalog.resolve_type!("PressKit") }
        assert_includes demodulized.message, "Unknown type PressKit"
        assert_includes demodulized.message, "Allowed types: Folder, Kit"
        rejected = assert_raises(RecordingStudioApi::NotFoundError) do
          catalog.resolve_type!("RecordingStudioPresskits::PressKit")
        end
        assert_includes rejected.message, "Unknown type RecordingStudioPresskits::PressKit"
        assert_includes rejected.message, "Allowed types: Folder, Kit"
        assert_includes operations.type_schema.fetch(:enum), "PressKit"
        refute_includes operations.type_schema.fetch(:enum), "Kit"
      end
    end
  end

  def test_blank_public_name_falls_back_to_the_demodulized_class_name
    with_isolated_api_configuration do
      register_tree_type("RecordingStudioPresskits::PressKit")
      with_public_name("RecordingStudioPresskits::PressKit", :public, "  ") do
        catalog = RecordingStudioMcp::Catalog.new(api: :public)

        assert_includes catalog.type_schema.fetch(:enum), "PressKit"
        assert_equal "RecordingStudioPresskits::PressKit", catalog.resolve_type!("PressKit")
        rejected = assert_raises(RecordingStudioApi::NotFoundError) do
          catalog.resolve_type!("RecordingStudioPresskits::PressKit")
        end
        assert_includes rejected.message, "Allowed types: PressKit"
      end
    end
  end

  def with_public_name(type_name, api_name, public_name, &)
    require "delegate"
    original = RecordingStudioApi.method(:recordable_registration_for)
    wrapped = lambda { |name, **kwargs|
      registration = original.call(name, **kwargs)
      requested = kwargs[:api] || kwargs["api"]
      next registration unless name.to_s == type_name.to_s && requested.to_s == api_name.to_s

      wrapper = SimpleDelegator.new(registration)
      wrapper.define_singleton_method(:public_name) { public_name }
      wrapper
    }
    RecordingStudioApi.stub(:recordable_registration_for, wrapped, &)
  end

  def test_clashing_public_names_show_full_class_names_and_warn
    with_isolated_api_configuration do
      register_tree_type("Alpha::EmbargoKit")
      register_tree_type("Beta::EmbargoKit")
      register_tree_type("Folder")
      warnings = []
      logger = Object.new
      logger.define_singleton_method(:warn) { |message| warnings << message }
      catalog = RecordingStudioMcp::Catalog.new(api: :public)

      Rails.stub(:logger, logger) do
        enum = catalog.type_schema.fetch(:enum)

        assert_includes enum, "Alpha::EmbargoKit"
        assert_includes enum, "Beta::EmbargoKit"
        assert_includes enum, "Folder"
        refute_includes enum, "EmbargoKit"
      end

      warning = warnings.join("\n")
      assert_includes warning, "Alpha::EmbargoKit"
      assert_includes warning, "Beta::EmbargoKit"
      assert_includes warning, "public_name"
      assert_includes warning, "API public"

      error = assert_raises(RecordingStudioApi::InvalidActionInputError) { catalog.resolve_type!("EmbargoKit") }
      assert_includes error.message, "matches more than one registered type"
      assert_includes error.message, "Alpha::EmbargoKit"
      assert_includes error.message, "Beta::EmbargoKit"
      assert_equal "Alpha::EmbargoKit", catalog.resolve_type!("Alpha::EmbargoKit")
      assert_equal "Alpha::EmbargoKit", catalog.describe("Alpha::EmbargoKit").fetch("type")
      assert_equal "Folder", catalog.describe("Folder").fetch("type")
    end
  end
end
