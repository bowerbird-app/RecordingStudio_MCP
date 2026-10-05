# frozen_string_literal: true

module ApplicationHelper
  def dummy_registered_apps_path
    "/admin/screens/oauth_clients"
  end

  def dummy_sidebar_item(text:, href:, icon:)
    render FlatPack::Sidebar::Item::Component.new(
      text: text,
      href: href,
      icon: icon,
      active: current_page?(href)
    )
  end

  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    recording_studio_page_nav(
      title: title,
      page_nav_back_url: back_url,
      page_nav_back_label: back_label
    )

    recording_studio_page_nav_right do
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
    end
  end
end
