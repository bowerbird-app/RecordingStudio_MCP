require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Dummy fixture keys for Active Record encryption (event webhook secrets).
    config.active_record.encryption.primary_key = "dummyPrimaryKeyBytes32charsxx"
    config.active_record.encryption.deterministic_key = "dummyDeterministicKey32charsxx"
    config.active_record.encryption.key_derivation_salt = "dummyKeyDerivationSalt32charsx"

    # Configure generators to use UUID primary keys
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Oauth 0.6.0 appends db/migrate/20261005000001_add_self_registered_apps_*.
    # Dummy already has 20261005000001_dummy_add_oauth_central_relay_rules.rb.
    # Keep that dummy filename. The generator copy of self-registered apps lives
    # at 20261006011812_*. Drop the engine migrate path so versions do not clash.
    # Oauth creates stay in schema.rb; later Oauth deltas are dummy copies.
    initializer "dummy.omit_oauth_engine_migrations",
                after: "recording_studio_oauth.append_migrations" do |app|
      migrate = app.config.paths["db/migrate"]
      kept = migrate.to_a.reject { |path| path.to_s.include?("RecordingStudio_Oauth") }
      migrate.instance_variable_set(:@paths, kept)
    end
  end
end
