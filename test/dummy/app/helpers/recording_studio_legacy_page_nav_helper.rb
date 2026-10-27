# frozen_string_literal: true

# Admin 2.5.1 still calls recording_studio_page_nav. Recording Studio 6.1
# removed that helper. Map the old kwargs onto Flatpack PageNav.
module RecordingStudioLegacyPageNavHelper
  def recording_studio_page_nav(title: nil, page_nav_back_url: nil, page_nav_back_label: nil,
                                page_nav_anchor_url: nil, page_nav_anchor_label: nil, **)
    content_for(:title, title) if title.present?

    kwargs = { round: true, style: :default }
    kwargs[:back_href] = page_nav_back_url if page_nav_back_url.present?
    kwargs[:back_tooltip] = page_nav_back_label if page_nav_back_label.present?
    kwargs[:anchor_href] = page_nav_anchor_url if page_nav_anchor_url.present?
    kwargs[:anchor_tooltip] = page_nav_anchor_label if page_nav_anchor_label.present?
    flat_pack_page_nav(**kwargs)
  end
end
