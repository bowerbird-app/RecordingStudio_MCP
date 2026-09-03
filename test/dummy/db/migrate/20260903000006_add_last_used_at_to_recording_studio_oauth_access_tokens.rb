# frozen_string_literal: true

class AddLastUsedAtToRecordingStudioOauthAccessTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_oauth_access_tokens, :last_used_at, :datetime
  end
end
