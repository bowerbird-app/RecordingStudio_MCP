# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- MCP admin (`:mcp`) lists ops MCP connection paths: `/recording_studio_mcp/apis/operations` and `/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations`, plus a hint to register ChatGPT and Grok Bot in Registered apps with `api_key: "operations"`. No OauthClient seeding. Public MCP and Workspace are unchanged.

## [0.9.0] - 2026-10-07

Staff/ops MCP clients authorize on the operations named API. Public MCP authorize is unchanged.

### Added
- Named-API MCP resource identities at `{mcp_mount_path}/apis/{api_key}` (for example `/recording_studio_mcp/apis/operations`). RFC 9728 metadata and `WWW-Authenticate` point `authorization_servers` at `/recording_studio_oauth/apis/{api_key}`.
- `RecordingStudioMcp.draw_named_api_well_known` for origin well-known on those paths. Draw it before Oauth `draw_origin_well_known`.
- Dummy names an `operations` API, registers `ops_ping` there, and covers ops MCP authorize with an operations OauthClient.

### Notes
- `api_key: "operations"` is the named API label, not a secret.
- Dummy and the development Gemfile pin `recording_studio_oauth` to git tag `v0.6.2` (ops clients + AdminRoot Connect).
- Oauth named-API registries still list only the API identifier, not MCP. Ops authorize/token should omit `resource` until Oauth registers `{mcp_mount}/apis/{api_key}`. Public MCP `resource` stays registered.

### Upgrade notes
- Bump to `0.9.0`.
- Pin Oauth `v0.6.2`.
- Call `RecordingStudioMcp.draw_named_api_well_known(self)` in host routes before Oauth origin well-known.
- Hosts that want ops MCP: define `config.api :operations`, register an operations OauthClient, Connect at `/recording_studio_oauth/apis/operations/oauth/authorize`, and point the MCP client at `/recording_studio_mcp/apis/operations`.

## [0.8.0] - 2026-10-06

### Added
- ChatGPT MCP Events webhook delivery on the existing authenticated MCP endpoint. `server/discover` advertises `"events": {}` when `config.events_enabled` is true (default false).
- `events/list`, `events/subscribe`, and `events/unsubscribe`. The first event is `recording.updated`, filtered by `recording_id`, driven by the same host `register_event` catalog as `notifications/resources/updated`. Hosts may add `event.webhook_event` schemas for more events.
- Signed Standard Webhooks deliveries (`webhook-id`, `webhook-timestamp`, `webhook-signature`, `X-MCP-Subscription-Id`), callback challenge verification, HTTPS-only public callbacks, and an outbound host allowlist hook.
- `recording_studio_mcp_event_subscriptions` (secret encrypted with Active Record encryption). Dummy enables events, saves a page to fire `recording.updated`, and has a local signed receiver at `/mcp_event_receiver`.

### Notes
- SSE progress, `resources/subscribe`, and `notifications/resources/updated` are unchanged. Polling, streaming delivery, and `gap` / `terminated` notifications are not implemented.

### Upgrade notes
- Bump to `0.8.0`.
- Run `bin/rails generate recording_studio_mcp:migrations` and `bin/rails db:migrate`.
- Set `config.events_enabled = true` to advertise events and accept subscriptions. Optional: `event_subscription_ttl`, `event_subscriptions_per_principal`, `event_callback_host_allowed`.
