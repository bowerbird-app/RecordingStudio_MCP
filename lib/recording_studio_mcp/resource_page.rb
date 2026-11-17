# frozen_string_literal: true

module RecordingStudioMcp
  class ResourcePage
    def initialize(scope, after_id:, page_size:)
      @scope = scope
      @after_id = after_id
      @page_size = page_size
    end

    def recordings
      page.fetch(:rows)
    end

    def more?
      page.fetch(:more)
    end

    private

    attr_reader :scope, :after_id, :page_size

    def page
      @page ||= build_page
    end

    def build_page
      fetched = fetch
      { rows: fetched.first(page_size), more: fetched.size > page_size }
    end

    def fetch
      return memory_rows unless relation?

      rows = limited_relation.to_a
      preload_recordables(rows.first(page_size))
      rows
    end

    def relation?
      scope.respond_to?(:arel_table) && scope.respond_to?(:reorder) && scope.respond_to?(:limit)
    end

    def limited_relation
      after_relation.reorder(id: :asc).limit(page_size + 1)
    end

    def after_relation
      return scope if after_id.nil?
      return scope.none unless after_id.match?(ResourceCursor::UUID)

      scope.where(scope.arel_table[:id].gt(after_id))
    end

    def memory_rows
      rows = memory_source
      rows = rows.select { |row| row.id.to_s.downcase > after_id.to_s } if after_id
      rows.sort_by { |row| row.id.to_s.downcase }.first(page_size + 1)
    end

    def memory_source
      return [] if scope.nil?
      return Array(scope.order(:id)) if scope.respond_to?(:order)

      Array(scope)
    end

    def preload_recordables(records)
      targets = records.select { |record| recordable_association?(record) }
      return if targets.empty?

      ActiveRecord::Associations::Preloader.new(records: targets, associations: :recordable).call
    end

    def recordable_association?(record)
      record.class.respond_to?(:reflect_on_association) && record.class.reflect_on_association(:recordable)
    end
  end
end
