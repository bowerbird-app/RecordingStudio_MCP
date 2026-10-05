# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DummyPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
    end
    sign_in @user
    load Rails.root.join("db/seeds.rb").to_s
  end

  test "pages index lists accessible pages with an inline save form" do
    page = Page.find_by!(title: "Getting Started")
    recording = RecordingStudio::Recording.find_by!(recordable: page)

    get pages_path

    assert_response :success
    assert_includes response.body, "Pages"
    assert_includes response.body, "Getting Started"
    assert_includes response.body, "Save page"
    assert_includes response.body, "Ping watchers"
    assert_select "form[action=?][method=?]", page_path(recording), "post"
    assert_includes response.body, "flat-pack-sidebar-layout"
  end

  test "saving a page revises through recording studio and flashes" do
    page = Page.find_by!(title: "Getting Started")
    recording = RecordingStudio::Recording.find_by!(recordable: page)
    before = recording.recordable.title

    patch page_path(recording), params: { title: "Inspector can watch this" }

    assert_redirected_to pages_path
    follow_redirect!
    assert_includes response.body, "Saved. Watchers can read it again."
    recording.reload
    assert_equal "Inspector can watch this", recording.recordable.title
    refute_equal before, recording.recordable.title
  end

  test "ping watchers fires the dummy custom event" do
    page = Page.find_by!(title: "Getting Started")
    recording = RecordingStudio::Recording.find_by!(recordable: page)
    notified = []
    RecordingStudioMcp.stub(:notify, lambda { |name, recording:|
      notified << [name, recording.id]
    }) do
      post comment_page_path(recording)
    end

    assert_redirected_to pages_path
    follow_redirect!
    assert_includes response.body, "Pinged the watchers."
    assert_equal [["page commented", recording.id]], notified
  end
end
