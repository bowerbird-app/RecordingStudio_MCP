# Recording Studio MCP

Mount this engine on a Recording Studio host. It exposes a remote MCP HTTP endpoint. Access is user-delegated OAuth. Domain actions come from Recording Studio API. This gem is a protocol adapter. It is not a second API and not an authorization server.

People Connect an app. The app gets its own Accessible grant. MCP then uses that same grant. The app does not act as the person.

## What you get

A Streamable HTTP MCP endpoint on the host. Unauthenticated calls return `401` with `WWW-Authenticate` pointing at MCP's own RFC 9728 protected-resource metadata (`/.well-known/oauth-protected-resource/recording_studio_mcp`). That document sets `resource` to the MCP URL and `authorization_servers` to Oauth. Clients authorize with authorization-code + PKCE S256 against Oauth (`/oauth/authorize`). Token exchange stays on API `POST /recording_studio_api/oauth/token`. MCP authenticates the Bearer with `RecordingStudioApi.access_grant_from_authorization_header`. The issued Bearer intentionally works for both the named API and MCP; both resolve the same AccessGrant.

Authorization is Recording Studio Accessible through that AccessGrant. Same grant as API. No Pundit. No OAuth scopes.

`tools/list` advertises the named API bound to the OauthClient. The surface depends on what that API registered.

Hosts opt in to live updates with `RecordingStudioMcp.register_event`, next to skill registration. The dummy registers `recording updated` (built-in after-save trigger) and `page commented` (host `notify`). Unregistered events never notify. `notify` with an unknown name raises `ArgumentError`. Initialize advertises `resources.subscribe` only when at least one event is registered. Event registration stays in this gem; it is not an API `register_endpoint`.

```ruby
RecordingStudioMcp.register_event("recording updated") do |event|
  event.on :recording_updated
  event.types "Page", "Document"
  event.if { |recording| recording.published? }
end
RecordingStudioMcp.register_event("comment added")
RecordingStudioMcp.notify("comment added", recording: comment.recording)
```

`register_event("recording updated")` with no block is the built-in trigger for every recordable type. That same registration is the `recording.updated` MCP Event (filter `recording_id`) when `config.events_enabled` is true.

ChatGPT can subscribe with `events/list`, `events/subscribe`, and `events/unsubscribe` on the same authenticated MCP endpoint. Deliveries are signed Standard Webhooks POSTs. SSE progress, `resources/subscribe`, and `notifications/resources/updated` stay as they are. Hosts add more events with `event.webhook_event(name, description:, arguments:, payload:)`.

```ruby
RecordingStudioMcp.configure do |config|
  config.events_enabled = true
  # config.event_subscription_ttl = 24.hours
  # config.event_subscriptions_per_principal = 50
  # config.event_callback_host_allowed = ->(host) { host.end_with?(".example") }
end
```

Run `bin/rails generate recording_studio_mcp:migrations` and `bin/rails db:migrate` so `recording_studio_mcp_event_subscriptions` exists. Secrets use Active Record encryption.

Accessible recordings are MCP resources at `recording://{id}`. `resources/list`, `resources/read`, and `resources/templates/list` use the same AccessGrant as tools. Skill files stay on `skill://…` URIs. Subscribe uses the same access check. The update notification carries the URI only.

A saved change (`record!`, `revise`, `log_event!`) on a subscribed recording is delivered **after commit**, onto that connection's queue. The listening stream's own writer drains the queue. A slow or dead subscriber is dropped (bounded queue + write timeout). The save request does not write sockets.

Subscriptions are process-local. On Postgres, MCP fans out `LISTEN`/`NOTIFY` with the event name and recording id. Each process re-checks access and its local subscribers. Other databases stay in-process: a save on worker B does not reach a subscriber on worker A.

Tree hosts register recordable types. They get six parameterized tools: `list`, `show`, `create`, `update`, `capability_action`, and `describe`. `type` is an enum of those types. Call `describe` for operations, typed writable fields, required fields, allowed values, enabled capability action input contracts, and parent rules. Unknown type or action errors name the allowed set.

Create and update send writable fields at the request root (`title`, not `attributes`). `list` accepts `pagination_token` from `meta.next_pagination_token`.

Catalog-only hosts register `RecordingStudioApi.register_endpoint` routes and no recordable types. They get one MCP tool per endpoint. The tool name is the endpoint name. Path tokens and `input_contract` fields become `inputSchema` arguments. There is no `describe` hop and no empty tree tool list.

Mixed hosts get tree tools first, then endpoint tools sorted by name. Do not register an endpoint named `list`, `show`, `create`, `update`, `capability_action`, or `describe`.

Tree tools stay parameterized over the recordable tree. They are not one MCP tool per OpenAPI path. Registered endpoints are a different registry. Each one is its own tool.

Tool results include MCP `structuredContent`. The initialize `instructions` match the grant's surface. Hosts may set `instructions_suffix`, and endpoint-only initialize text now teaches clients to call `tools/list` and fetch item details before generating UI. Tools include display titles. Annotations mark reads, writes, retries (`idempotentHint`), closed Studio scope (`openWorldHint: false`), destructive capability actions, and GET versus mutating endpoint verbs. The server reports `tools.listChanged: false`. Call `tools/list` again when you need a fresh list.

Handlers call the same API resource actions, capability actions, and registered endpoint handlers. MCP does not serve records when API access is disabled.

Staff register the client in Oauth. There is no Dynamic Client Registration.

## Skills

Domain gems own the `SKILL.md` files. They register those files as candidates. `RecordingStudioMcp` keeps the registry and speaks MCP. It chooses which registered skills the current client may see. The client sees that filtered set.

Registering a skill stores a candidate. Exposure is a separate decision.

A domain gem registers the file it ships.

```ruby
RecordingStudioMcp.register_skill(
  "research-publications",
  path: RecordingStudioPublications::Engine.root.join(
    "skills/research-publications/SKILL.md"
  )
)
```

`available_if` is optional. Leave it out and the skill is available. The proc receives the current `access_grant` and allows the skill only when it returns `true`.

```ruby
RecordingStudioMcp.register_skill(
  "research-publications",
  path: ".../SKILL.md",
  available_if: ->(access_grant:) { true }
)
```

`config.skill_policy` is the host filter. Leave it unset and every available skill may be exposed. The proc receives the skill and the current `access_grant`.

```ruby
config.skill_policy = ->(skill:, access_grant:) { true }
```

A skill is exposed when it is registered, `available_if` allows it, and `skill_policy` allows it. `skills/list`, `skills/get`, and `resources/read` share that decision. The resource URI is `skill://<name>/SKILL.md`. `skills/list` omits a hidden skill. The same URI then fails for `skills/get` and `resources/read`.

## Transport checks

Native clients may omit `Origin`. When a browser sends `Origin`, it must match the MCP host origin or an entry in `allowed_origins`; otherwise MCP returns `403`. Configure additional trusted browser origins in `config/initializers/recording_studio_mcp.rb`.

After initialize, or after `server/discover`, clients send the negotiated version in `MCP-Protocol-Version`. They may repeat it in `params._meta["io.modelcontextprotocol/protocolVersion"]`. A missing header uses that `_meta` version, then MCP's `2025-03-26` backwards-compatible default. Unsupported versions return `400`. A header that disagrees with that `_meta` key returns JSON-RPC `-32020`.

`server/discover` is the `2026-07-28` DiscoverResult: `supportedVersions` lists `2025-03-26`, `2025-06-18`, `2025-11-25`, and `2026-07-28`; `capabilities` and `instructions` match initialize; `serverInfo` lives under result `_meta`.

On `2025-03-26`, `2025-06-18`, and `2025-11-25`, unsolicited updates go out on the GET SSE listening stream. Initialize returns `Mcp-Session-Id`. Later POSTs and the GET send that header. Clients call `resources/subscribe` and `resources/unsubscribe` by URI. An unknown or inaccessible subscribe URI returns `-32002`.

On `2026-07-28`, GET is not a notification stream. Clients POST `subscriptions/listen` with `notifications.resourceSubscriptions`. The response is a long-lived SSE stream. The first event is `notifications/subscriptions/acknowledged`. Later `notifications/resources/updated` events include `io.modelcontextprotocol/subscriptionId`. When the server ends the stream, it writes the listen completion result, then closes. `resources/subscribe` is not a method on this revision. `resources/read` not found is `-32602`. Cacheable result fields are only on this revision.

## Progress notifications

A `tools/call` may stream Server-Sent Events on that same POST when **both** are true:

- `params._meta.progressToken` is a string or an integer
- the `Accept` header includes `text/event-stream`

Anything else, including `tools/list`, `ping`, a missing/null/wrong-type token, or a client that only sends `*/*`, stays today's single JSON body. A bad token is ignored: the tool still runs, with no progress and no error.

Streamed calls share the JSON dispatcher, authorization, serializers, and error mapping. Progress messages are `notifications/progress` with **no JSON-RPC `id`**. They echo the token. The last SSE event is the JSON-RPC result or error with the original request `id`, then the stream closes.

MCP uses a **Rack streaming response body** (`response_body` assigned an enumerable `SseStreamBody`), not `ActionController::Live`. Live would wrap every MCP action in an extra thread and change JSON-only calls. The enumerable runs after filters and auth, writes each SSE frame as the tool produces it, then closes. Puma emits those chunks without waiting for the handler to finish.

Auth, origin checks, API availability, and rate limits run **before** the stream opens. Unauthorized or disabled-API requests stay JSON.

`RecordingStudioApi` handler contexts accept an optional `progress_reporter`. MCP passes the per-request context when a `tools/call` is streaming (progress token + SSE). REST and JSON-only MCP calls leave it `nil`. Handlers call `context.progress(current:, total:, message:)` and `context.cancelled?`. Those methods no-op / return false without a reporter. MCP does not monkey-patch API classes.

If the client disconnects, MCP stops writing, marks the context disconnected, and closes the writer. Handlers stop only if they check `cancelled?`. Completed work is not rolled back. `notifications/cancelled` is unchanged (accepted notification, no body).

Each POST still writes **one** usage log. Streamed duration is until completion or disconnect. Tokens, tool arguments, and SSE payloads are not stored.

### Host / proxy buffering

Progress is useless if a proxy holds the body until the tool finishes. For the dummy app under Puma:

```bash
curl -N --no-buffer \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"demo_progress","arguments":{},"_meta":{"progressToken":"walk-1"}}}' \
  http://127.0.0.1:3000/recording_studio_mcp
```

Use `-N` / `--no-buffer`. Set these so frames leave the process as they are written:

- MCP already sends `Content-Type: text/event-stream`, `Cache-Control: no-cache, no-store`, and `X-Accel-Buffering: no` (nginx).
- Do not put `Rack::Deflater` or ETag middleware in front of MCP. `no-store` skips Rails ETag buffering; gzip still buffers.
- ngrok: no extra flag. If a TLS proxy buffers, disable proxy buffering for this path.
- Puma workers/threads: one in-flight streamed call occupies that thread until it ends.

The dummy host registers `demo_progress` through `RecordingStudioApi.register_endpoint` (five delayed steps). That tool is dummy-only, not part of this gem’s production tree. Dummy also registers `recording updated` and `page commented`, and sets `events_enabled`. **Pages** lists pages the signed-in person can see. Each row has an inline save form (same `revise` path as home **Edit recording**) so a subscribed client gets `notifications/resources/updated` and ChatGPT webhook subscribers get `recording.updated`. **Ping watchers** fires the custom SSE event. **Webhook inbox** at `/mcp_event_receiver` is a local signed receiver.

## Install

1. Add the gem. Pin Recording Studio `~> 4.2`, API `~> 0.6.1`, Oauth `v0.6.0`, and `recording_studio_admin ~> 2.0`.
2. Install and mount API and Oauth first. Allow `RecordingStudioOauth::OauthAuthorization` in Accessible `access_actor_types`.
3. Run `bin/rails generate recording_studio_mcp:install`.
4. Draw Oauth origin well-known: `RecordingStudioOauth::ProtectedResourceRegistry.draw_origin_well_known(self)`. Or alias `/.well-known/oauth-protected-resource/recording_studio_mcp` to MCP's metadata controller. ChatGPT and API clients keep using `/recording_studio_oauth/.well-known/oauth-protected-resource`.
5. Register a public PKCE OauthClient for the MCP app. People Connect. Then call MCP with the issued Bearer token.

Host authentication stays on the host. Dummy uses Devise. Do not add Users as a dependency of this gem.

This gem ships no end-user product UI. Staff admin is the MCP section when `recording_studio_admin` is mounted. Dummy host chrome may use Flatpack. Oauth owns Connect screens.

## Admin

Staff admin is the MCP admin section. The Usage widget charts calls from the last 4 weeks and opens the Usage screen. Registered apps opens Oauth's section. It is not the `/docs/mcp` probe.

Each authenticated or failed POST to the MCP endpoint writes one usage log. The row stores the method, the tool or skill name, the status, the duration, and the API client id. It does not store the token or the tool arguments. Daily totals live in `recording_studio_mcp_usage_daily_metrics`.

```bash
bin/rails generate recording_studio_mcp:migrations
bin/rails db:migrate
rake recording_studio_mcp:maintain_usage
```

1. Allow the section on the admin root.

```ruby
recording_studio_admin_sections do
  section :mcp
end
```

2. Link MCP from the admin home section.

```ruby
link :mcp, text: "MCP", url: ->(context) { context.admin_section_path("mcp") }
```

## Watching a recording (dummy)

Sign in, Connect Seed MCP App, mint a token on `/docs/mcp`, then:

```bash
# Legacy: initialize, subscribe, listen on GET
curl -sS -D - -o /tmp/init.json \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl"}}}' \
  http://127.0.0.1:3000/recording_studio_mcp
# Copy Mcp-Session-Id from the response headers. List resources, subscribe, then:
curl -N --no-buffer \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: text/event-stream" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -H "Mcp-Session-Id: $SESSION" \
  http://127.0.0.1:3000/recording_studio_mcp
```

On another tab, click **Edit recording** on `/`. The GET stream should emit `notifications/resources/updated`. Read the URI again.

For `2026-07-28`, keep the listen POST open instead of GET:

```bash
curl -N --no-buffer \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -d '{"jsonrpc":"2.0","id":1,"method":"subscriptions/listen","params":{"notifications":{"resourceSubscriptions":["recording://ID"]}}}' \
  http://127.0.0.1:3000/recording_studio_mcp
```

## Dummy

`test/dummy` on port 3000. Sign in with `admin@admin.com` / `Password`. Seed MCP App is a public OauthClient. Studio Workspace starts Connected. Site name `Studio` comes from Site settings when Connect needs it. Seeds also write sample MCP usage for the last 4 weeks, then roll those calls into daily totals. Loading seeds again replaces that sample.

The dummy-only docs page at `/docs/mcp` can mint a real test token, probe MCP, and sample-POST the endpoint. It is not the product.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

## Version

0.8.0
