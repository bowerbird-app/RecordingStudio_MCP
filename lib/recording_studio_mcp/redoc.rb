# frozen_string_literal: true

module RecordingStudioMcp
  module Redoc
    VERSION = "3.1.0"
    DIRECTORY = File.expand_path("../../vendor/redoc", __dir__)
    LOGO_MINI_TOKEN = "redoc-logo-mini.local"
    LOGO_MINI_FULL_TOKEN = "redoc-logo-mini-full.local"
    FILES = {
      "redoc.js" => ["redoc.standalone.js", "text/javascript"],
      "logo-mini.svg" => ["logo-mini.svg", "image/svg+xml"],
      "logo-mini-full.svg" => ["logo-mini-full.svg", "image/svg+xml"]
    }.freeze

    module_function

    def file_for(asset)
      filename, content_type = FILES[asset.to_s]
      return unless filename

      path = File.join(DIRECTORY, filename)
      return unless File.file?(path)

      [path, content_type]
    end

    def javascript_for(mount)
      path, = file_for("redoc.js")
      return unless path

      prefix = mount.to_s.chomp("/")
      File.binread(path).force_encoding(Encoding::UTF_8)
          .gsub(LOGO_MINI_FULL_TOKEN, "#{prefix}/logo-mini-full.svg")
          .gsub(LOGO_MINI_TOKEN, "#{prefix}/logo-mini.svg")
    end
  end
end
