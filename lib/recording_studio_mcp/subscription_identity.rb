# frozen_string_literal: true

require "digest"

module RecordingStudioMcp
  module SubscriptionIdentity
    module_function

    def generate(principal_id:, callback_url:, event_name:, arguments:)
      material = [
        principal_id.to_s,
        callback_url.to_s,
        event_name.to_s,
        CanonicalJson.dump(arguments || {})
      ].join("\n")
      "sub_#{Digest::SHA256.hexdigest(material)}"
    end
  end
end
