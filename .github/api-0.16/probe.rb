# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"

# Loads Recording Studio API 0.16 sources and checks the path MCP relies on:
# AccessGrant resolves authorized_by from the OAuth credential, and action
# contexts read that through AuthorizingHuman. The app Gemfile stays on API
# tag v0.14.1 because recording_studio_oauth 0.13.1 still requires API < 0.15.
# CI checks this file out from PR #61. It is not part of the default test run.

root = File.expand_path(ENV.fetch("RECORDING_STUDIO_API_ROOT"))
version_source = File.read(File.join(root, "lib/recording_studio_api/version.rb"))
raise "expected API 0.16 sources in #{root}" unless version_source.include?('VERSION = "0.16.')

%w[
  authorized_by
  authorizing_human
  access_grant
  progress_reporting
  action_context
  registered_endpoint_context
  resource_operation_context
].each do |name|
  require File.join(root, "lib/recording_studio_api/#{name}.rb")
end

person = Class.new do
  attr_reader :id

  def initialize(id)
    @id = id
  end

  def self.name
    "AuthorizingPerson"
  end
end
human = person.new(41)
authorization = Struct.new(:manager_actor).new(human)
credential = Struct.new(:oauth_authorization).new(authorization)
api_client = Object.new

grant = RecordingStudioApi::AccessGrant.new(
  api_client: api_client,
  credential: credential,
  access_recording: nil
)
raise "grant did not resolve authorized_by" unless grant.authorized_by.equal?(human)

keyword_names = lambda do |context_class|
  context_class.instance_method(:initialize).parameters.filter_map do |type, name|
    name if %i[key keyreq].include?(type)
  end
end

[RecordingStudioApi::ActionContext, RecordingStudioApi::ResourceOperationContext,
 RecordingStudioApi::RegisteredEndpointContext].each do |context_class|
  names = keyword_names.call(context_class)
  if names.include?(:authorized_by) || names.include?(:oauth_authorization)
    raise "#{context_class} accepts authorized_by"
  end
end

action = RecordingStudioApi::ActionContext.new(
  recording: nil,
  api_client: api_client,
  credential: credential,
  access_recording: nil,
  access_grant: grant,
  root_recording: nil,
  params: {}
)
resource = RecordingStudioApi::ResourceOperationContext.new(
  recording: nil,
  recordable_type: "Page",
  resource_name: "pages",
  api_client: api_client,
  credential: credential,
  access_recording: nil,
  access_grant: grant,
  root_recording: nil,
  api_version: "v1",
  params: {},
  request_params: {},
  scoped_recordings: nil,
  parent_recording: nil
)
endpoint = RecordingStudioApi::RegisteredEndpointContext.new(
  api_client: api_client,
  credential: credential,
  access_recording: nil,
  access_grant: grant,
  root_recording: nil,
  params: {}
)

[action, resource, endpoint].each do |context|
  raise "#{context.class} authorized_by" unless context.authorized_by.equal?(human)

  merged = context.with_authorized_by(authorized_by_type: "Spoofed", authorized_by_id: "spoof", note: "keep")
  kept = merged[:authorized_by_type] == "AuthorizingPerson" && merged[:authorized_by_id] == 41
  kept &&= merged[:note] == "keep"
  raise "#{context.class} with_authorized_by #{merged.inspect}" unless kept
  raise "authorized_by_id was stringified" unless merged[:authorized_by_id].equal?(41)
end

plain = RecordingStudioApi::AccessGrant.new(
  api_client: api_client,
  credential: Object.new,
  access_recording: nil
)
raise "api credential resolved a human" unless plain.authorized_by.nil?

puts "api 0.16 authorized_by ok"
