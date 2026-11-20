# frozen_string_literal: true

module Dummy
  class Leaf < ApplicationRecord
    self.table_name = "pages"

    recording_studio_recordable label: "Leaf", root: false, allowed_parent_types: %w[Workspace Folder]
  end
end
