# frozen_string_literal: true

module RecordingStudioMcp
  module Documentation
    module Openapi
      module ActionDocs
        module_function

        def documented_title(action, type_name, api_key)
          per_type = per_type_title(action, type_name)
          return per_type if per_type.present?

          shared = raw_copy(action)["title"]
          return if shared.blank?
          return shared if title_fits_type?(shared, type_name, api_key)

          nil
        end
        private_class_method :documented_title

        def per_type_title(action, type_name)
          return unless action.respond_to?(:openapi_for)

          title = hash_title(typed_openapi(action, type_name))
          return if title.blank? || title == raw_copy(action)["title"]

          title
        end
        private_class_method :per_type_title

        def typed_openapi(action, type_name)
          action.openapi_for(type: type_name, action: action.name)
        end
        private_class_method :typed_openapi

        def hash_title(openapi)
          return unless openapi.is_a?(Hash)

          openapi[:title].presence || openapi["title"].presence
        end
        private_class_method :hash_title

        def title_fits_type?(title, type_name, api_key)
          return true if tokens_named?(title, type_tokens(type_name, api_key))

          other_type_tokens(type_name, api_key).none? { |token| title_names?(title, token) }
        end
        private_class_method :title_fits_type?

        def tokens_named?(title, tokens)
          tokens.any? { |token| title_names?(title, token) }
        end
        private_class_method :tokens_named?

        def title_names?(title, token)
          title.match?(/\b#{Regexp.escape(token)}\b/i)
        end
        private_class_method :title_names?

        def other_type_tokens(type_name, api_key)
          RecordingStudioMcp::Catalog.new(api: api_key).type_names.flat_map do |other|
            next [] if other.to_s == type_name.to_s

            type_tokens(other, api_key)
          end.uniq
        end
        private_class_method :other_type_tokens

        def type_tokens(type_name, api_key)
          usable_tokens(type_name, api_key)
        end
        private_class_method :type_tokens

        def usable_tokens(type_name, api_key)
          label = RecordingStudio.recordable_type_label(type_name).to_s
          tokens = [public_type_token(type_name, api_key), label, label.singularize, type_name.to_s.demodulize]
          tokens.map { |token| token.to_s.strip }.uniq.reject { |token| token.length < 3 }
        end
        private_class_method :usable_tokens

        def public_type_token(type_name, api_key)
          registration = RecordingStudioApi.recordable_registration_for(type_name, api: api_key)
          return if registration.nil?

          registration.public_name
        end
        private_class_method :public_type_token

        def type_label(type_name)
          RecordingStudio.recordable_type_label(type_name).to_s.singularize
        end
        private_class_method :type_label
      end
    end
  end
end
