# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_03_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "action_key", null: false
    t.string "actor_id"
    t.string "actor_type"
    t.string "blast_radius"
    t.datetime "created_at", null: false
    t.boolean "destructive"
    t.string "error_class"
    t.text "error_message"
    t.string "event_id", null: false
    t.string "http_method"
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.string "outcome", null: false
    t.string "record_id"
    t.string "record_type"
    t.string "recording_studio_event_id"
    t.string "request_id"
    t.string "required_role"
    t.string "resource_key", null: false
    t.string "surface_key"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["event_id"], name: "index_admin_audit_logs_on_event_id", unique: true
    t.index ["occurred_at"], name: "index_admin_audit_logs_on_occurred_at"
    t.index ["outcome"], name: "index_admin_audit_logs_on_outcome"
    t.index ["resource_key", "action_key"], name: "index_admin_audit_logs_on_resource_key_and_action_key"
  end

  create_table "admin_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.integer "role", default: 0, null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_api_admin_apis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_admin_apis_on_key", unique: true
  end

  create_table "recording_studio_api_api_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_credential_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["api_credential_id"], name: "idx_on_api_credential_id_89874cbf51"
    t.index ["expires_at"], name: "index_recording_studio_api_api_access_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_recording_studio_api_api_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_api_api_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "api_key", default: "public", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "index_recording_studio_api_api_clients_on_access_recording_id", unique: true
    t.index ["api_key"], name: "index_recording_studio_api_api_clients_on_api_key"
  end

  create_table "recording_studio_api_api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id", null: false
    t.uuid "api_client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.string "token_public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_103368144f"
    t.index ["api_client_id"], name: "index_recording_studio_api_api_credentials_on_api_client_id"
    t.index ["api_client_id"], name: "index_recording_studio_api_credentials_on_active_client", unique: true, where: "(revoked_at IS NULL)"
    t.index ["token_digest"], name: "index_recording_studio_api_api_credentials_on_token_digest", unique: true
    t.index ["token_public_id"], name: "index_recording_studio_api_api_credentials_on_token_public_id", unique: true
  end

  create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_key", default: "public", null: false
    t.datetime "created_at", null: false
    t.date "metric_date", null: false
    t.bigint "request_count", default: 0, null: false
    t.string "request_method", null: false
    t.string "route_name", null: false
    t.integer "status_class", null: false
    t.datetime "updated_at", null: false
    t.integer "upper_bound_ms", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class", "upper_bound_ms"], name: "index_rs_api_daily_latency_histogram_on_dimensions", unique: true
    t.index ["metric_date"], name: "idx_on_metric_date_8723beba88"
  end

  create_table "recording_studio_api_api_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_name"
    t.string "api_key", default: "public", null: false
    t.bigint "client_error_count", default: 0, null: false
    t.string "controller_name"
    t.datetime "created_at", null: false
    t.bigint "duration_count", default: 0, null: false
    t.integer "duration_max_ms", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.date "metric_date", null: false
    t.bigint "rate_limited_count", default: 0, null: false
    t.bigint "request_count", default: 0, null: false
    t.string "request_method", null: false
    t.string "route_name", null: false
    t.bigint "server_error_count", default: 0, null: false
    t.integer "status_class", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class"], name: "index_rs_api_daily_metrics_on_dimensions", unique: true
    t.index ["metric_date"], name: "index_recording_studio_api_api_daily_metrics_on_metric_date"
  end

  create_table "recording_studio_api_api_request_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "action_name"
    t.uuid "api_client_id"
    t.uuid "api_credential_id"
    t.string "api_key", default: "public", null: false
    t.string "controller_name"
    t.datetime "created_at", null: false
    t.integer "duration_ms", null: false
    t.string "error_class"
    t.string "error_message"
    t.datetime "occurred_at", null: false
    t.boolean "rate_limited", default: false, null: false
    t.string "remote_ip"
    t.string "request_id"
    t.string "request_method", null: false
    t.jsonb "request_params", default: {}, null: false
    t.string "request_path", null: false
    t.uuid "root_recording_id"
    t.string "route_name"
    t.integer "status_code", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["api_client_id", "occurred_at"], name: "index_rs_api_request_logs_on_client_and_time"
    t.index ["api_credential_id", "occurred_at"], name: "index_rs_api_request_logs_on_credential_and_time"
    t.index ["api_key", "occurred_at"], name: "index_rs_api_request_logs_on_api_and_time"
    t.index ["occurred_at"], name: "index_recording_studio_api_api_request_logs_on_occurred_at"
    t.index ["request_id"], name: "index_recording_studio_api_api_request_logs_on_request_id"
    t.index ["request_path"], name: "index_recording_studio_api_api_request_logs_on_request_path"
    t.index ["status_code"], name: "index_recording_studio_api_api_request_logs_on_status_code"
  end

  create_table "recording_studio_api_api_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "api_access_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.jsonb "runtime_overrides", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_api_settings_on_key", unique: true
  end

  create_table "recording_studio_attachable_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "attachment_kind", null: false
    t.bigint "byte_size", null: false
    t.string "content_type", null: false
    t.text "description"
    t.string "name", null: false
    t.string "original_filename", null: false
    t.index ["attachment_kind", "content_type"], name: "idx_rs_attachable_kind_type"
    t.index ["attachment_kind"], name: "idx_on_attachment_kind_d683071625"
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.index ["action", "occurred_at"], name: "index_rs_events_on_action_and_occurred_at"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_rs_events_on_actor_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id", "occurred_at", "created_at"], name: "index_rs_events_on_recording_and_timeline", order: { occurred_at: :desc, created_at: :desc }
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
  end

  create_table "recording_studio_oauth_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.uuid "oauth_authorization_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_recording_studio_oauth_access_tokens_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_7313b03aba"
    t.index ["token_digest"], name: "index_recording_studio_oauth_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_oauth_authorization_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "oauth_authorization_id", null: false
    t.string "redirect_uri", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.index ["code_digest"], name: "idx_on_code_digest_bcebd970b4", unique: true
    t.index ["expires_at"], name: "index_recording_studio_oauth_authorization_codes_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_4cb485335a"
  end

  create_table "recording_studio_oauth_authorizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.datetime "created_at", null: false
    t.uuid "manager_access_recording_id", null: false
    t.uuid "manager_actor_id", null: false
    t.string "manager_actor_type", null: false
    t.uuid "oauth_client_id", null: false
    t.datetime "revoked_at"
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_94e16371a2"
    t.index ["manager_access_recording_id"], name: "idx_on_manager_access_recording_id_ee8e9d6f9c"
    t.index ["manager_actor_type", "manager_actor_id"], name: "index_rs_oauth_authorizations_on_manager_actor"
    t.index ["oauth_client_id", "manager_actor_type", "manager_actor_id", "manager_access_recording_id"], name: "index_rs_oauth_authorizations_unique_active", unique: true, where: "(revoked_at IS NULL)"
    t.index ["oauth_client_id"], name: "index_recording_studio_oauth_authorizations_on_oauth_client_id"
    t.index ["revoked_at"], name: "index_recording_studio_oauth_authorizations_on_revoked_at"
  end

  create_table "recording_studio_oauth_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_key", default: "public", null: false
    t.string "client_id", null: false
    t.string "client_secret_digest"
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "redirect_uris", default: [], null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_recording_studio_oauth_clients_on_api_key"
    t.index ["client_id"], name: "index_recording_studio_oauth_clients_on_client_id", unique: true
  end

  create_table "recording_studio_oauth_refresh_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "oauth_authorization_id", null: false
    t.uuid "replaced_by_id"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_recording_studio_oauth_refresh_tokens_on_expires_at"
    t.index ["oauth_authorization_id"], name: "idx_on_oauth_authorization_id_a1e93340c5"
    t.index ["replaced_by_id"], name: "index_recording_studio_oauth_refresh_tokens_on_replaced_by_id"
    t.index ["token_digest"], name: "index_recording_studio_oauth_refresh_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.index ["parent_recording_id"], name: "idx_rs_attachable_parent_active", where: "(((recordable_type)::text = 'RecordingStudioAttachable::Attachment'::text) AND (trashed_at IS NULL))"
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["recordable_type", "recordable_id"], name: "index_rs_unique_root_recording_per_recordable", unique: true, where: "(parent_recording_id IS NULL)"
    t.index ["root_recording_id", "parent_recording_id"], name: "index_rs_recordings_on_root_and_parent"
    t.index ["root_recording_id", "recordable_type", "recordable_id"], name: "index_rs_recordings_on_root_and_recordable"
    t.index ["root_recording_id"], name: "idx_rs_attachable_root_active", where: "(((recordable_type)::text = 'RecordingStudioAttachable::Attachment'::text) AND (trashed_at IS NULL))"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "recording_studio_site_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_oauth_access_tokens", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_oauth_authorization_codes", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_oauth_authorizations", "recording_studio_oauth_clients", column: "oauth_client_id"
  add_foreign_key "recording_studio_oauth_refresh_tokens", "recording_studio_oauth_authorizations", column: "oauth_authorization_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
end
