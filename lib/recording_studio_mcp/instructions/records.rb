# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    module_function

    def walk_section(surface)
      return unless surface.tree_enabled?

      section("Walk your records", walk_lines(surface))
    end

    def walk_lines(surface)
      names = surface.tree_tool_names
      lines = []
      lines << workspace_line if names.include?("list")
      lines << "Records nest by parent_id."
      lines << "root_id is the workspace, not the parent."
      lines << parent_line if surface.list_parent_id? && names.include?("list")
      lines << pagination_line if names.include?("list")
      lines
    end

    def workspace_line
      "Call list with the workspace type and no parent_id to find workspaces."
    end

    def parent_line
      "List with parent_id, then show."
    end

    def pagination_line
      "For the next page, pass meta.next_pagination_token as pagination_token."
    end

    def changes_section(surface)
      section("Make changes", change_lines(surface))
    end

    def change_lines(surface)
      names = surface.tree_tool_names
      lines = []
      lines << fields_line if names.intersect?(%w[create update])
      lines << idempotency_line if names.include?("create")
      lines
    end

    def fields_line
      "Send writable fields at the top level, not under attributes."
    end

    def idempotency_line
      "Send the same idempotency_key on a retried create to avoid a duplicate."
    end

    def guides_section(access_grant)
      section("Guides", ["This server may offer skills. Read the relevant ones.", suffix_text(access_grant)])
    end

    private_class_method :walk_section, :walk_lines, :workspace_line, :parent_line, :pagination_line,
                         :changes_section, :change_lines, :fields_line, :idempotency_line, :guides_section
  end
end
