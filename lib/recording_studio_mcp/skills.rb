# frozen_string_literal: true

require "digest"
require "pathname"
require "yaml"

module RecordingStudioMcp
  module Skills
    module SkillName
      PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      LENGTH = (1..64)
      PREFIX = "skill://"
      SUFFIX = "/SKILL.md"

      module_function

      def parse(name)
        return nil unless name.is_a?(String)
        return nil unless LENGTH.cover?(name.length)
        return nil unless PATTERN.match?(name)

        name
      end

      def from_uri(uri)
        return nil unless uri.is_a?(String)
        return nil unless uri.start_with?(PREFIX) && uri.end_with?(SUFFIX)

        parse(uri.delete_prefix(PREFIX).delete_suffix(SUFFIX))
      end
    end

    Registration = Data.define(:name, :path, :available_if) do
      def uri
        "skill://#{name}/SKILL.md"
      end
    end

    class SkillCatalog
      include Enumerable

      def self.empty
        new({})
      end

      def initialize(entries)
        @entries = entries.freeze
      end

      def add(registration)
        self.class.new(@entries.merge(registration.name => registration))
      end

      def fetch(name)
        @entries.fetch(name)
      end

      def each(&)
        @entries.each_value(&)
      end
    end

    class Document
      class << self
        def read(registration)
          raw = File.binread(registration.path.to_s)
          text = utf8(raw)
          return nil if text.nil?

          frontmatter = Frontmatter.parse(text, registration.name)
          return nil if frontmatter.nil?

          assemble(registration, raw, text, frontmatter)
        rescue StandardError
          nil
        end

        private

        def utf8(raw)
          text = raw.dup.force_encoding(Encoding::UTF_8)
          text if text.valid_encoding?
        end

        def assemble(registration, raw, text, frontmatter)
          new(
            uri: registration.uri,
            frontmatter: frontmatter,
            digest: "sha256:#{Digest::SHA256.hexdigest(raw)}",
            size: raw.bytesize,
            text: text
          )
        end
      end
      private_class_method :new

      def initialize(uri:, frontmatter:, digest:, size:, text:)
        @uri = uri
        @frontmatter = frontmatter
        @digest = digest
        @size = size
        @text = text
      end

      attr_reader :uri, :frontmatter, :digest, :size, :text

      def card
        {
          uri: uri,
          frontmatter: frontmatter,
          resources: [{ uri: uri, digest: digest, size: size }]
        }
      end

      def content
        { uri: uri, mimeType: "text/markdown", text: text }
      end
    end

    module Frontmatter
      FENCE = "---"

      class << self
        def parse(text, expected_name)
          body = fenced_body(text)
          return nil if body.nil?

          loaded = YAML.safe_load(body, aliases: false)
          return nil unless acceptable?(loaded, expected_name)

          loaded
        rescue StandardError
          nil
        end

        private

        def fenced_body(text)
          lines = text.lines
          return nil unless opening_fence?(lines.first)

          body = []
          lines.drop(1).each do |line|
            return body.join if closing_fence?(line)

            body << line
          end
          nil
        end

        def opening_fence?(line)
          ["#{FENCE}\n", "#{FENCE}\r\n"].include?(line)
        end

        def closing_fence?(line)
          ["#{FENCE}\n", "#{FENCE}\r\n", FENCE].include?(line)
        end

        def acceptable?(loaded, expected_name)
          return false unless loaded.is_a?(Hash)
          return false unless json_safe?(loaded)
          return false unless nonblank_string?(loaded["name"]) && loaded["name"] == expected_name

          nonblank_string?(loaded["description"])
        end

        def nonblank_string?(value)
          value.is_a?(String) && !value.strip.empty?
        end

        def json_safe?(value)
          case value
          when String, Numeric, TrueClass, FalseClass, NilClass
            true
          when Array
            value.all? { |item| json_safe?(item) }
          when Hash
            value.each_key.all?(String) && value.each_value.all? { |item| json_safe?(item) }
          else
            false
          end
        end
      end
    end

    Result = Data.define(:payload)
    InvalidParams = Class.new
    Unavailable = Class.new

    class << self
      def answer(method_name, params, access_grant:)
        case method_name
        when "skills/list"
          list_answer(params, access_grant)
        when "skills/get"
          fetch_answer(params, access_grant) { |document| { skill: document.card } }
        when "resources/read"
          fetch_answer(params, access_grant) { |document| { contents: [document.content] } }
        else
          InvalidParams.new
        end
      end

      private

      def list_answer(params, access_grant)
        return InvalidParams.new unless params.is_a?(Hash) && params["cursor"].nil?

        cards = cards_for(RecordingStudioMcp.exposed_skills(access_grant: access_grant))
        return Unavailable.new if cards.nil?

        Result.new(payload: complete(skills: cards))
      end

      def fetch_answer(params, access_grant)
        registration = exposed_registration(params, access_grant)
        return registration if registration.is_a?(InvalidParams)

        document = Document.read(registration)
        return Unavailable.new if document.nil?

        Result.new(payload: complete(yield(document)))
      end

      def exposed_registration(params, access_grant)
        return InvalidParams.new unless params.is_a?(Hash)

        name = SkillName.from_uri(params["uri"])
        return InvalidParams.new if name.nil?

        found = RecordingStudioMcp.exposed_skills(access_grant: access_grant).find { |skill| skill.name == name }
        found || InvalidParams.new
      end

      def cards_for(registrations)
        cards = []
        registrations.each do |registration|
          document = Document.read(registration)
          return nil if document.nil?

          cards << document.card
        end
        cards
      end

      def complete(extra)
        { resultType: "complete" }.merge(extra).merge(ttlMs: 0, cacheScope: "private")
      end
    end
  end
end
