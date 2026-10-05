# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class DummyEditPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.find_or_create_by!(email: "admin@admin.com") do |record|
      record.password = "Password"
      record.password_confirmation = "Password"
    end
    sign_in @user
    load Rails.root.join("db/seeds.rb").to_s
  end

  test "home offers a flatpack edit recording button that saves a change" do
    page = Page.find_by!(title: "Getting Started")
    recording = RecordingStudio::Recording.find_by!(recordable: page)
    before = recording.recordable.title

    get root_path

    assert_response :success
    assert_includes response.body, "Edit recording"
    assert_includes response.body, "Tweak this page"
    assert_select "form[action=?][method=?]", save_page_change_path, "post"
    assert_includes response.body, "flat-pack-sidebar-layout"

    post save_page_change_path

    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Saved. Watchers can read it again."
    recording.reload
    refute_equal before, recording.recordable.title
  end
end
