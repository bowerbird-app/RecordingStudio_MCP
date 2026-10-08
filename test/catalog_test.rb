# frozen_string_literal: true

require "test_helper"

class CatalogTest < Minitest::Test
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
      refute public_catalog.destroy_supported?

      assert_includes ops_catalog.type_names, "SupportPage"
      refute_includes ops_catalog.type_names, "Page"
      assert_includes ops_catalog.type_schema.fetch(:enum), "SupportPage"
      assert ops_catalog.destroy_supported?
      assert_equal ["SupportPage"], ops_catalog.destroy_type_names
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
