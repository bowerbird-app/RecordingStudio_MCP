# frozen_string_literal: true

class DummyAddOauthRegistrationPolicy < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:recording_studio_oauth_clients, :allow_registration)
      add_column :recording_studio_oauth_clients, :allow_registration, :boolean, null: false, default: false
    end
  end
end
