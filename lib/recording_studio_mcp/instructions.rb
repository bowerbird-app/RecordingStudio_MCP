# frozen_string_literal: true

module RecordingStudioMcp
  module Instructions
    GENERAL_TOOL_NAMES = %w[list show create update delete capability_action describe read_skill].freeze
    DESCRIBE_RETURN_ITEMS = [
      "the type paragraph",
      "included tools",
      "skills via read_skill",
      "relationships",
      "allowed parents",
      "writable fields"
    ].freeze
    DESCRIBE_RETURN_ACTIONS = "available actions"

    module_function

    def text(access_grant: nil, api: nil, surface: nil)
      surface ||= ToolSurface.for(access_grant: access_grant, api: api)
      sections_for(surface, access_grant).compact.join("\n\n")
    end

    def sections_for(surface, access_grant)
      [
        sign_in_section,
        find_tools_section(surface),
        walk_section(surface),
        changes_section(surface),
        guides_section(access_grant),
        live_section,
        metrics_section(surface),
        named_routes_section(surface)
      ]
    end

    def sign_in_section
      section("Sign in", "Use an OAuth Bearer token. It has the same access as the app.")
    end

    def find_tools_section(surface)
      section("Find your tools", find_tool_lines(surface))
    end

    def find_tool_lines(surface)
      [
        "Call tools/list.",
        "A live session receives notifications/tools/list_changed when that list changes.",
        "Reconnect after a deploy if the app ignores that notice.",
        "ping checks the connection.",
        describe_line(surface),
        general_tools_line(surface),
        per_type_page_line(surface)
      ]
    end

    def describe_line(surface)
      return unless surface.tree_enabled? && surface.tree_tool_names.include?("describe")

      line = "Call describe for #{describe_returns(surface.catalog.capability_actions_advertised?)}"
      before = describe_before(surface.tree_tool_names)
      return "#{line}." if before.nil?

      "#{line} before you #{before}."
    end

    def describe_returns(include_actions)
      parts = DESCRIBE_RETURN_ITEMS.dup
      parts << DESCRIBE_RETURN_ACTIONS if include_actions
      listed(parts)
    end

    def describe_before(names)
      parts = []
      parts << "create" if names.include?("create")
      parts << "run an action" if names.include?("capability_action")
      parts.empty? ? nil : parts.join(" or ")
    end

    def general_tools_line(surface)
      return unless surface.tree_enabled?

      names = GENERAL_TOOL_NAMES.select { |name| surface.tree_tool_names.include?(name) }
      names << "ping"
      extra = ", plus named route tools" if surface.endpoints_enabled?
      "Agents get only the general tools #{listed(names)}#{extra}."
    end

    def listed(names)
      return names.first.to_s if names.one?

      "#{names[0..-2].join(', ')}, and #{names.last}"
    end

    def per_type_page_line(surface)
      return unless surface.tree_enabled?

      "A per-type page shows how to call a general tool with that type or action. " \
        "It uses the same checks. It is not a separate tool."
    end

    def suffix_text(access_grant)
      source = RecordingStudioMcp.configuration.instructions_suffix
      return if source.nil?

      raw = source.respond_to?(:call) ? source.call(access_grant: access_grant) : source
      return unless raw.is_a?(String)

      text = raw.strip
      text.empty? ? nil : text
    end

    def section(title, lines)
      body = Array(lines).flatten.compact
      return if body.empty?

      "## #{title}\n\n#{body.join("\n\n")}"
    end

    private_class_method :sections_for, :sign_in_section, :find_tools_section, :find_tool_lines,
                         :describe_line, :describe_before, :general_tools_line, :listed,
                         :per_type_page_line, :suffix_text, :section
  end
end

require_relative "instructions/records"
require_relative "instructions/extras"
