# frozen_string_literal: true

class DummyAddOauthCentralRelayRules < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:recording_studio_oauth_clients, :use_central_relay)
      add_column :recording_studio_oauth_clients, :use_central_relay, :boolean, null: false, default: false
    end
    unless column_exists?(:recording_studio_oauth_clients, :allowed_return_patterns)
      add_column :recording_studio_oauth_clients, :allowed_return_patterns, :jsonb, null: false, default: []
    end
    unless column_exists?(:recording_studio_oauth_clients, :exact_return_urls)
      add_column :recording_studio_oauth_clients, :exact_return_urls, :jsonb, null: false, default: []
    end
  end
end
