# frozen_string_literal: true

class AddSelfRegisteredAppsToRecordingStudioOauthClients < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_oauth_clients, :self_registered, :boolean, null: false, default: false
    add_column :recording_studio_oauth_clients, :token_endpoint_auth_method, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE recording_studio_oauth_clients
          SET token_endpoint_auth_method = CASE
            WHEN confidential THEN 'client_secret_basic'
            ELSE 'none'
          END
        SQL
        change_column_null :recording_studio_oauth_clients, :token_endpoint_auth_method, false
      end
    end
  end
end
