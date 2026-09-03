# frozen_string_literal: true

require "test_helper"

class CatalogTest < Minitest::Test
  FakeClient = Struct.new(:api_key)
  FakeGrant = Struct.new(:api_client)

  def test_api_from_grant_uses_oauth_client_named_api
    grant = FakeGrant.new(FakeClient.new("public"))

    assert_equal "public", RecordingStudioMcp::Catalog.api_from(grant)
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
