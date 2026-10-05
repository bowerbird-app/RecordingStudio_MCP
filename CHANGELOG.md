# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-10-05

### Added
- Protocol revisions `2025-03-26`, `2025-06-18`, `2025-11-25` (legacy initialize + `resources/subscribe` + GET SSE), and `2026-07-28` (modern `subscriptions/listen`). Each request uses the negotiated version.
- `RecordingStudioMcp.register_event` names events that may notify. A block can set `on`, `types`, and `if`. `register_event("recording updated")` with no block keeps the built-in after-save trigger for every recordable type. Custom names fire only through `RecordingStudioMcp.notify`. `notify` with an unregistered name raises `ArgumentError`. `resources.subscribe` is advertised only when at least one event is registered.
- Recordings the AccessGrant can reach are MCP resources at stable `recording://{id}` URIs. `resources/list`, `resources/read`, `resources/templates/list`, and subscribe share those access checks. The wire update is URI only.
- A save never writes the SSE stream. After commit, MCP enqueues onto each subscribed connection. The stream writer drains the queue. A full queue or a write timeout drops that subscriber and leaves the saver alone.
- On Postgres, delivery fans out with `LISTEN`/`NOTIFY` (event name + recording id). Each process re-checks AccessGrant and its local subscribers. Other databases stay in-process.
- Legacy clients subscribe with `resources/subscribe` / `resources/unsubscribe` and receive `notifications/resources/updated` on the GET SSE listening stream (`Mcp-Session-Id` in memory, dropped on disconnect).
- `2026-07-28` clients use `subscriptions/listen` with `resourceSubscriptions`. The listen POST reuses the Streamable HTTP SSE writer. The first event is `notifications/subscriptions/acknowledged`; later updates carry `io.modelcontextprotocol/subscriptionId`. When the server ends the stream, it writes the listen completion result before close.
- `server/discover` lists the versions this endpoint speaks.
- Dummy registers `recording updated` and `page commented`. `/pages` lists pages the signed-in person can see, each with an inline save form. Home still has Edit recording.

### Notes
- Event registration lives in this gem, next to `register_skill`. It is not an API `register_endpoint`. The API gem has no notification registry.
- `tools.listChanged` stays `false`. No persistent subscriptions. No OAuth dynamic client registration.
- `2026-07-28` `resources/read` not found is `-32602`. `2025-xx` keeps `-32002`. Legacy subscribe for an unknown or inaccessible URI is `-32002`. Cacheable result fields (`resultType`, `ttlMs`, `cacheScope`) appear only on `2026-07-28` sessions.

### Upgrade notes
- Bump to `0.7.0`. Optional: `RecordingStudioMcp.register_event("recording updated")` when clients should watch items. The no-block form is the same as today's built-in trigger.
- Hosts that need a custom event: `register_event("comment added")` then `RecordingStudioMcp.notify("comment added", recording:)`.
- Clients that want live updates must subscribe after initialize. On `2025-03-26` / `2025-06-18` / `2025-11-25`, open GET with `Accept: text/event-stream` and send `Mcp-Session-Id`. On `2026-07-28`, POST `subscriptions/listen` instead of GET.
- Any `record!` / `revise` / `log_event!` on a subscribed recording counts as updated when a registered event uses `on :recording_updated`, including content, attachments stored as events, and status.
- Postgres hosts: run more than one Puma worker. Updates fan out through `LISTEN`/`NOTIFY`. Other databases notify only subscribers in the same process.

## [0.6.0] - 2026-10-05

### Added
- Streamable HTTP progress for `tools/call` when `params._meta.progressToken` is a string or integer and `Accept` includes `text/event-stream`. Other methods stay single JSON.
- Per-request MCP context with `progress` / `disconnected?`, a thread-safe SSE writer, and one usage log per POST (duration until completion or disconnect).
- Dummy-only `demo_progress` registered endpoint that emits delayed progress then a final result.

### Changed
- Pin `recording_studio_api` to `~> 0.6` (git tag `v0.6.0`).
- Pin `recording_studio_oauth` to git tag `v0.5.6`.
- Dummy and development also pin Accessible `v0.11.1`, Admin `v2.0.4`, Attachable `v0.7.1`, Site settings `v0.1.3`, Root Switchable `v0.5.3`, and Recording Studio `v4.2.2`.
- Dummy Accessible schema includes access invitations and stores access roles as strings (`view`, `edit`, `admin`).
- Streamed `tools/call` passes the per-request context as API `progress_reporter`. JSON-only calls leave it `nil`.
- Removed `RecordingStudioMcp.register_host_tool`. Dummy `demo_progress` registers through `RecordingStudioApi.register_endpoint` and calls `context.progress` / `context.cancelled?`.

### Notes
- Protocol versions remain `2025-03-26` and `2025-06-18`. `tools.listChanged` stays `false`.
- When Accessible 0.11 is loaded, MCP exposes `RecordingStudio::Access.roles` as `AccessRoles::ORDER` so API 0.6 can rank grants.

### Upgrade notes
- Depend on `recording_studio_api ~> 0.6`. Streamed `tools/call` needs API 0.6 `progress_reporter` on endpoint and capability contexts.
- Pin Oauth `v0.5.6` (API `>= 0.5.2, < 0.7`).
- Stop calling `RecordingStudioMcp.register_host_tool`. Register extra tools with `RecordingStudioApi.register_endpoint`.
- Hosts on Accessible 0.11: run Accessible migrations. MCP defines `RecordingStudio::Access.roles` from `AccessRoles::ORDER` when that map is missing.

## [0.5.0] - 2026-09-30

### Added
- The gem registers a Recording Studio Admin section titled MCP admin. Its Registered apps link opens Oauth's admin section.
- MCP usage is logged per call and rolled up by day. The MCP admin section charts the last 4 weeks and links to a Usage screen.

### Upgrade notes
- Depend on `recording_studio_admin ~> 2.0` (Oauth 0.2 already pulls it in).
- On the admin root, allow `section :mcp`.
- On the admin home section, link MCP to `admin_section_path("mcp")`.
- Run `bin/rails generate recording_studio_mcp:migrations` and `bin/rails db:migrate`.
- Schedule `rake recording_studio_mcp:maintain_usage` so raw logs older than 30 days are deleted after the daily totals are rebuilt.
- Hosts that do not mount admin still record usage. They do not see the widget.

## [0.4.0] - 2026-09-30

### Added
- `RecordingStudioMcp.register_skill` registers candidate skills. Clients discover and read the exposed set with `skills/list`, `skills/get`, and `resources/read`.

### Upgrade notes
- Optional. Existing `initialize`, `ping`, `tools/list`, and `tools/call` clients keep working. A host that wants a narrower skill set sets `config.skill_policy`.

## [0.3.2] - 2026-09-14

### Added
- MCP-owned RFC 9728 protected-resource metadata at `/.well-known/oauth-protected-resource/recording_studio_mcp` (host alias). `resource` is the MCP URL. `authorization_servers` still points at Oauth.
- `config.mcp_mount_path` (default `/recording_studio_mcp`).
- After boot, syncs `RecordingStudioOauth.configuration.mcp_mount_path` so Oauth 0.2+ authorize accepts the MCP resource identity.

### Changed
- Unauthenticated MCP calls return `WWW-Authenticate` `resource_metadata` for the MCP path, not the unsuffixed origin well-known URL.
- Default `oauth_protected_resource_path` is now `/.well-known/oauth-protected-resource/recording_studio_mcp`.

### Upgrade notes
- Pin Oauth to `>= 0.2.0` (branch `cursor/mcp-protected-resource-identity-607a` until tagged).
- Draw Oauth origin well-known in the host: `RecordingStudioOauth::ProtectedResourceRegistry.draw_origin_well_known(self)`. That serves MCP and API path-inserted metadata. Origin unsuffixed `/.well-known/oauth-protected-resource` is 404 by default; ChatGPT and API clients keep using `/recording_studio_oauth/.well-known/oauth-protected-resource`.
- You may still alias the MCP well-known path to `recording_studio_mcp/oauth_discoveries#protected_resource` if you prefer MCP-owned discovery over Oauth's draw helper.
- Set `config.mcp_mount_path` if the engine is not mounted at `/recording_studio_mcp`, and keep `oauth_protected_resource_path` aligned with RFC 9728 (`/.well-known/oauth-protected-resource` + mount path).

## [0.3.1] - 2026-09-10

### Added
- Optional `config.instructions_suffix`. A String or `->(access_grant:) { ... }` is appended after the built-in initialize instructions.

### Changed
- Endpoint initialize text now teaches `tools/list`, names the endpoint-only grant, and tells clients to fetch item detail before generating UI.

### Upgrade notes
- Optional `config.instructions_suffix` (String or `->(access_grant:) { ... }`). Richer default endpoint initialize blurb. No OAuth, tool, or connect changes. Hosts that want product-specific MCP guidance set the suffix.

## [0.3.0] - 2026-09-09

### Added
- One MCP tool per `RecordingStudioApi.register_endpoint` entry. Tool name matches the endpoint name. Path tokens and `input_contract` fields become the tool `inputSchema`.
- Dynamic initialize instructions from the grant's tool surface.

### Changed
- Tree tools (`list`, `show`, `create`, `update`, `capability_action`, `describe`) appear only when the named API has recordable types.
- Catalog-only hosts no longer advertise empty tree tools.
- Mixed hosts list tree tools first, then endpoint tools sorted by name.
- `tools/call` for a GET registered endpoint counts as a read for API rate limiting.

### Upgrade notes
- Pin `recording_studio_api` to `~> 0.5.4`.
- Catalog-only hosts now see endpoint tools on `tools/list`. Clients that assumed the six tree names always exist need to read the advertised list.
- Tree tools are omitted when the named API has no recordable types. Do not tell those clients to call `describe` before create.
- Do not `register_endpoint` with a tree tool name. MCP raises a configuration error if an endpoint is named `list`, `show`, `create`, `update`, `capability_action`, or `describe`.

## [0.2.1] - 2026-09-07

### Added
- Dummy-only “Try MCP” and “Sample POST” on `/docs/mcp`: mint a Seed MCP App token, probe MCP, then prove the Bearer grant resolves through the same post-auth MCP path (without nesting a full inner HTTP request that resets Current).

### Upgrade notes
- Dummy-only helper. No host upgrade required.

## [0.2.0] - 2026-09-07

### Added
- Initialize instructions that teach clients to describe types before writes, use top-level fields, and follow pagination tokens.
- Typed writable-field details and capability action input contracts in `describe`.
- Explicit tool titles plus read-only, destructive, idempotent, and closed-world (`openWorldHint: false`) annotations.
- Origin allowlisting and `MCP-Protocol-Version` validation for Streamable HTTP requests.

### Changed
- Report `tools.listChanged: false` because this endpoint does not send live tool-list updates.
- Clarify that the Oauth Bearer intentionally works with both MCP and its named API through the same AccessGrant.

### Upgrade notes
- `describe.writable_fields` now contains field objects instead of field-name strings. Read each object's `name`, `required`, `type`, optional `allowed_values`, and optional `immutable_on_update`.
- Browser clients with a cross-origin MCP connection must add their exact origin to `allowed_origins`. Native clients without an `Origin` header continue to work.
- Send the negotiated `MCP-Protocol-Version` after initialize. Missing headers use the MCP `2025-03-26` backwards-compatible default; unsupported versions return `400`.

## [0.1.0] - 2026-09-03

### Added
- Mountable engine with a remote Streamable HTTP MCP endpoint.
- Unauthenticated calls return `401` with `WWW-Authenticate` pointing at Oauth RFC 9728 protected-resource metadata.
- Bearer authentication through `RecordingStudioApi.access_grant_from_authorization_header`.
- Authorization through the same Accessible AccessGrant as API.
- Parameterized tools `list`, `show`, `create`, `update`, `capability_action`, and `describe` over the named API the OauthClient is bound to.
- Grant-aware `tools/list` with a `type` enum, `listChanged: true`, and `structuredContent` on tool results.
- Create and update take writable fields at the request root. `list` accepts `pagination_token`.
- Dummy host that stacks Oauth + API + MCP, seeds a public PKCE client, and proves Connect then a tool call.

### Upgrade notes
- First release. Mount after API and Oauth. Register the MCP app as an OauthClient. Do not add a second authorization server.

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.1.0
