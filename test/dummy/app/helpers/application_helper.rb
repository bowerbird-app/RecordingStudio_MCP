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
    content_for :title, title
    return if back_url.blank?

    flat_pack_page_nav(round: true, style: :default, back_href: back_url, back_tooltip: back_label)
  end
end
