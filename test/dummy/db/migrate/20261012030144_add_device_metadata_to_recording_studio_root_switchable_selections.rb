# frozen_string_literal: true

class AddDeviceMetadataToRecordingStudioRootSwitchableSelections < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:recording_studio_root_switchable_selections)

    add_column :recording_studio_root_switchable_selections, :device_label, :string, limit: 255 unless column_exists?(:recording_studio_root_switchable_selections, :device_label)
    add_column :recording_studio_root_switchable_selections, :device_platform, :string, limit: 255 unless column_exists?(:recording_studio_root_switchable_selections, :device_platform)
    add_column :recording_studio_root_switchable_selections, :device_browser, :string, limit: 255 unless column_exists?(:recording_studio_root_switchable_selections, :device_browser)
    add_column :recording_studio_root_switchable_selections, :device_type, :string, limit: 255 unless column_exists?(:recording_studio_root_switchable_selections, :device_type)
    add_column :recording_studio_root_switchable_selections, :user_agent, :text unless column_exists?(:recording_studio_root_switchable_selections, :user_agent)
  end

  def down
    return unless table_exists?(:recording_studio_root_switchable_selections)

    remove_column :recording_studio_root_switchable_selections, :user_agent if column_exists?(:recording_studio_root_switchable_selections, :user_agent)
    remove_column :recording_studio_root_switchable_selections, :device_type if column_exists?(:recording_studio_root_switchable_selections, :device_type)
    remove_column :recording_studio_root_switchable_selections, :device_browser if column_exists?(:recording_studio_root_switchable_selections, :device_browser)
    remove_column :recording_studio_root_switchable_selections, :device_platform if column_exists?(:recording_studio_root_switchable_selections, :device_platform)
    remove_column :recording_studio_root_switchable_selections, :device_label if column_exists?(:recording_studio_root_switchable_selections, :device_label)
  end
end
