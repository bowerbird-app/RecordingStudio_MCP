# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Overview
      module_function

      def markdown(surface)
        Instructions.text(api: surface.catalog.api, surface: surface)
      end
    end
  end
end
