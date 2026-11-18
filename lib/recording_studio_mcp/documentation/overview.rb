# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Overview
      module_function

      VIEW_ONLY_LINE = "A view-only connection gets the same text minus the Make changes part."

      def markdown(surface)
        text = Instructions.text(api: surface.catalog.api, surface: surface)
        return text unless text.include?("## Make changes")

        "#{text}\n\n#{VIEW_ONLY_LINE}"
      end
    end
  end
end
