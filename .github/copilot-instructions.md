# Project guidelines

## Architecture

This repository is the Recording Studio MCP addon. It is a mountable engine that exposes a remote Streamable HTTP MCP endpoint. Access is user-delegated OAuth. Domain actions come from Recording Studio API. This gem is a protocol adapter. It is not a second API and not an authorization server.

Keep the engine namespaced under `RecordingStudioMcp`. Treat `docs/gem_template/` as leftover template internals. Product docs are the top-level README.

Do not add Pundit, Doorkeeper, OmniAuth, Dynamic Client Registration, or Users as a gem dependency.

## UI

This gem ships no product UI. Dummy host chrome may use Flatpack. Oauth owns Connect screens.

## Testing

Run `bundle exec rake test:all` from the repository root. Cover both the gem suite and dummy suite. Dummy proves Connect then an MCP tool call with the issued Bearer token.
