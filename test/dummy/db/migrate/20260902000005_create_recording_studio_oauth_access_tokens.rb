# frozen_string_literal: true

class CreateRecordingStudioOauthAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_oauth_access_tokens, id: :uuid do |t|
      t.references :oauth_authorization,
                   null: false,
                   type: :uuid,
                   foreign_key: { to_table: :recording_studio_oauth_authorizations }
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :recording_studio_oauth_access_tokens, :token_digest, unique: true
    add_index :recording_studio_oauth_access_tokens, :expires_at
  end
end
