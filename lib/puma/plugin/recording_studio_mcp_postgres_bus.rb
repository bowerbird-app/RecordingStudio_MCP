# frozen_string_literal: true

require "puma/plugin"

# Opt-in Puma plugin for PostgresBus lifecycle under cluster mode.
#
# Single mode (no workers): after_initialize already starts the bus; this
# plugin's after_booted start! is idempotent.
#
# Cluster mode: stop in the master before fork, start in each worker after
# fork so LISTEN runs per worker — not in the master, and not only once in
# a preloaded parent that workers would inherit as a dead thread.
#
# In config/puma.rb:
#   plugin :recording_studio_mcp_postgres_bus
#
# Uses launcher.options[:workers] (public). Does not call private
# Launcher#clustered? (NoMethodError on Puma 7/8).
#
# Hooks guard with defined?(RecordingStudioMcp::PostgresBus) so they are safe
# when the app is not preloaded and constants are not loaded yet.
#
# Solid Queue's plugin may also fork after_booted. Those children keep the
# parent's @owner_pid, so PostgresBus at_exit is inert there. Do not start
# the bus again in Solid Queue children.
# Marker so PostgresBus can skip the cluster boot warning when this plugin is loaded.
module RecordingStudioMcp
  module PostgresBusPumaPlugin
    def self.active?
      true
    end
  end
end

Puma::Plugin.create do
  def start(launcher)
    if workers?(launcher)
      install_cluster_hooks(launcher)
    else
      install_single_hooks(launcher)
    end
  end

  private

  # Public API: options is attr_reader on Launcher; :workers is the DSL value.
  # Verified private clustered? raises NoMethodError on Puma 7.1 and 8.0.2.
  def workers?(launcher)
    launcher.options[:workers].to_i.positive?
  end

  def install_cluster_hooks(launcher)
    append_hook(launcher, :before_fork) { stop_bus_if_loaded }
    append_hook(launcher, :before_worker_boot) { start_bus_if_loaded }
  end

  def install_single_hooks(launcher)
    events = launcher.events
    if events.respond_to?(:after_booted)
      events.after_booted { start_bus_if_loaded }
    elsif events.respond_to?(:on_booted)
      events.on_booted { start_bus_if_loaded }
    end
  end

  def start_bus_if_loaded
    return unless defined?(RecordingStudioMcp::PostgresBus)

    RecordingStudioMcp::PostgresBus.start!
  end

  def stop_bus_if_loaded
    return unless defined?(RecordingStudioMcp::PostgresBus)

    RecordingStudioMcp::PostgresBus.stop!
  end

  # launcher.options is Puma::UserFileDefaultOptions (public). Hooks are
  # arrays of { block:, cluster_only: } hashes, same shape as DSL#process_hook.
  def append_hook(launcher, key, &block)
    options = launcher.options
    current = options.user_options[key]
    list = case current
           when nil then []
           when Array then current.dup
           else [current]
           end
    list << { block: block, cluster_only: true }
    options[key] = list
  end
end
