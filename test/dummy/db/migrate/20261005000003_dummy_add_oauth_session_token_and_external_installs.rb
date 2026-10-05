# frozen_string_literal: true

class DummyAddOauthSessionTokenAndExternalInstalls < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:recording_studio_oauth_clients, :session_token_provider)
      add_column :recording_studio_oauth_clients, :session_token_provider, :string
    end
    unless column_exists?(:recording_studio_oauth_clients, :session_token_audience)
      add_column :recording_studio_oauth_clients, :session_token_audience, :string
    end
    unless column_exists?(:recording_studio_oauth_clients, :session_token_secret_ciphertext)
      add_column :recording_studio_oauth_clients, :session_token_secret_ciphertext, :text
    end

    return if table_exists?(:recording_studio_oauth_external_installs)

    create_table :recording_studio_oauth_external_installs, id: :uuid do |t|
      t.uuid :oauth_client_id, null: false
      t.string :provider, null: false
      t.string :external_id, null: false
      t.uuid :root_recording_id
      t.string :connected_by_type
      t.uuid :connected_by_id

      t.timestamps
    end

    add_index :recording_studio_oauth_external_installs,
              %i[oauth_client_id provider external_id],
              unique: true,
              name: "index_rs_oauth_external_installs_on_client_provider_external"
    add_index :recording_studio_oauth_external_installs,
              %i[provider external_id],
              name: "index_rs_oauth_external_installs_on_provider_external"
    add_index :recording_studio_oauth_external_installs, :root_recording_id
    add_index :recording_studio_oauth_external_installs,
              %i[connected_by_type connected_by_id],
              name: "index_rs_oauth_external_installs_on_connected_by"

    add_foreign_key :recording_studio_oauth_external_installs,
                    :recording_studio_oauth_clients,
                    column: :oauth_client_id
    add_foreign_key :recording_studio_oauth_external_installs,
                    :recording_studio_recordings,
                    column: :root_recording_id
  end
end
