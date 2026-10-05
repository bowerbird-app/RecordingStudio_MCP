# Host pins

Ruby 3.3 or newer. Rails 8.1. Recording Studio `~> 4.2`. API `~> 0.6`. Oauth `v0.5.6`.

## 0.7.1

`server/discover` returns the `2026-07-28` DiscoverResult (`supportedVersions`, capabilities, instructions, cache fields, `serverInfo` in result `_meta`). ChatGPT-style clients that discover then call `tools/list` see tools. No host config change. Oauth pin is unchanged.

## 0.7.0

Optional `RecordingStudioMcp.register_event("recording updated")` so clients can watch items. A block may set `on :recording_updated`, `types`, and `if`. Custom names fire only via `RecordingStudioMcp.notify(name, recording:)`. Unregistered `notify` raises. `resources.subscribe` appears on initialize only after that registration.

Recordings the grant can reach are `recording://{id}` resources. Legacy clients subscribe with `resources/subscribe` and listen on GET SSE with `Mcp-Session-Id`. `2026-07-28` clients POST `subscriptions/listen` instead. Delivery is after commit, onto a per-connection queue the stream writer drains. Postgres fans out with `LISTEN`/`NOTIFY` (event name + id). Other databases notify only the saving process.

`server/discover` lists `2025-03-26`, `2025-06-18`, `2025-11-25`, and `2026-07-28`. `tools.listChanged` stays `false`.

## 0.6.0

Pin API to `~> 0.6` and Oauth to `v0.5.6`. Streamed `tools/call` passes the per-request MCP context as API `progress_reporter`. JSON-only calls leave it `nil`. `RecordingStudioMcp.register_host_tool` is gone. Extra tools register through `RecordingStudioApi.register_endpoint`. Protocol versions stay `2025-03-26` and `2025-06-18`. `tools.listChanged` stays `false`.

Hosts on Accessible 0.11 run Accessible migrations. When `RecordingStudio::Access.roles` is missing, MCP exposes `AccessRoles::ORDER` so API 0.6 can rank grants.

## 0.5.0

Depend on `recording_studio_admin ~> 2.0` (Oauth 0.2 already pulls it in). On the admin root, allow `section :mcp`. On the admin home section, link MCP to `admin_section_path("mcp")`. The section is titled MCP admin. It charts usage for the last 4 weeks, links to the Usage screen, and links to Oauth's Registered apps section.

Run `bin/rails generate recording_studio_mcp:migrations` and `bin/rails db:migrate`. That adds `recording_studio_mcp_usage_logs` and `recording_studio_mcp_usage_daily_metrics`. Schedule `rake recording_studio_mcp:maintain_usage` to rebuild yesterday and today, then delete raw logs older than 30 days. Hosts that do not mount admin still record usage. They do not see the widget.

## 0.4.0

Domain gems may register `SKILL.md` candidates with `RecordingStudioMcp.register_skill`. Exposure is separate. `available_if` and `config.skill_policy` both have to allow the current access grant. Clients read the exposed set with `skills/list`, `skills/get`, and `resources/read`. No OAuth or tool changes.

## 0.3.2

MCP advertises RFC 9728 protected-resource metadata whose `resource` is the MCP URL. `WWW-Authenticate` points at `/.well-known/oauth-protected-resource/recording_studio_mcp`. Oauth remains the authorization server and accepts that MCP `resource` identity.

Draw Oauth origin well-known in the host:

```ruby
RecordingStudioOauth::ProtectedResourceRegistry.draw_origin_well_known(self)
```

That serves MCP and API path-inserted documents. Origin unsuffixed `/.well-known/oauth-protected-resource` is 404 by default. ChatGPT and API clients keep using `/recording_studio_oauth/.well-known/oauth-protected-resource`. Clients that omit `resource` keep working.

Alternatively alias the MCP well-known path to `recording_studio_mcp/oauth_discoveries#protected_resource`.

## 0.3.1

Optional `config.instructions_suffix` (String or `->(access_grant:) { ... }`). Richer default endpoint initialize blurb. No OAuth, tool, or connect changes. Hosts that want product-specific MCP guidance set the suffix.

## 0.3.0

Pin API to `~> 0.5.4`. That release owns `register_endpoint` and `RegisteredEndpointContext`.

MCP now builds a tool surface from the OauthClient's named API:

- Recordable types present: advertise the six tree tools.
- Registered endpoints present: advertise one tool per endpoint name.
- Both: tree tools first, then endpoint tools sorted by name.
- Neither: `tools/list` is empty. Initialize still explains the Bearer grant.

Catalog-only hosts stop seeing `list` / `describe` with an empty type enum. Clients must call the endpoint tools directly. Path tokens are tool arguments.

Do not register an endpoint named `list`, `show`, `create`, `update`, `capability_action`, or `describe`. MCP raises `RecordingStudioApi::ConfigurationError` if those collide.

`tools/call` for a GET endpoint is a read for API rate limiting, same as `list`, `show`, and `describe`.

## 0.2.1

Dummy-only “Try MCP” and “Sample POST” on `/docs/mcp`. No host upgrade required.

Dummy GitHub tags used to prove Connect then MCP:

- Recording Studio `v4.2.2`
- Accessible `v0.11.1`
- API `v0.6.0`
- Oauth `v0.5.6`
- Admin `v2.0.4`
- Site settings `v0.1.3`
- Attachable `v0.7.1`
- Root Switchable `v0.5.3`
- Flatpack `v0.1.198`

Dummy stays on Devise. This gem does not depend on Users.

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```
