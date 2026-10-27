# frozen_string_literal: true

class DummyAddOauthPluginKey < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:recording_studio_oauth_clients, :plugin_key)
      add_column :recording_studio_oauth_clients, :plugin_key, :string
    end
    unless index_exists?(:recording_studio_oauth_clients, :plugin_key)
      add_index :recording_studio_oauth_clients, :plugin_key
    end
  end
end
