# Recording Studio MCP

Mount this engine on a Recording Studio host. It exposes a remote MCP HTTP endpoint. Access is user-delegated OAuth. Domain actions come from Recording Studio API. This gem is a protocol adapter. It is not a second API and not an authorization server.

People Connect an app. The app gets its own Accessible grant. MCP then uses that same grant. The app does not act as the person.

An OAuth tool call that writes through `record!`, `revise`, or `log_event!` also stores `authorized_by_type` and `authorized_by_id` on the event. Those are the class and id of the token's `OauthAuthorization#manager_actor`. The id is the record id, not a string copy. The event actor is API `write_actor` (`AccessGrant#actor`, the Accessible grant actor). When that actor is not the OAuth client, API stores the client as impersonator. `Current.actor` stays unset after the tool call. A client-credentials token has no `OauthAuthorization`, so MCP does not add those keys. Client-supplied `authorized_by_type` and `authorized_by_id` values are still removed on that client's writes, including a lone type or a lone id. MCP builds the access grant and passes the sign-in `authorized_by` into `AccessGrant`. The stamp reads that value on `record!` writes whose actor is the token's API client. The development lockfile pins API tag `v1.21.3` and Oauth tag `v0.26.0`. Other writes on the same thread are left alone. The stamp clears when the tool call ends. API `create` inserts the recording without an event. API `delete` hard-deletes the recording. RecordingStudio_api v0.21.0 defines `ResourceOperations::Base#delete_metadata` with `with_authorized_by`, and `Destroy` does not call it, so a delete still has no event row.

## What you get

A Streamable HTTP MCP endpoint on the host. Unauthenticated calls return `401` with `WWW-Authenticate` pointing at MCP's own RFC 9728 protected-resource metadata (`/.well-known/oauth-protected-resource/recording_studio_mcp`). That document sets `resource` to the MCP URL and `authorization_servers` to Oauth. Clients authorize with authorization-code + PKCE S256 against Oauth (`/oauth/authorize`). Token exchange stays on API `POST /recording_studio_api/oauth/token`. MCP authenticates the Bearer with `RecordingStudioApi.authenticate_authorization_header` and builds the same AccessGrant, passing sign-in `authorized_by`. The issued Bearer intentionally works for both that named API and that MCP path; both resolve the same AccessGrant.

Ops MCP uses the same Oauth + API stack, not a second OAuth server. An OauthClient with `api_key: "operations"` (a named API label, not a secret) authorizes at `/recording_studio_oauth/apis/operations/oauth/authorize`. The ops MCP resource is `/recording_studio_mcp/apis/operations`. Its well-known document points `authorization_servers` at `/recording_studio_oauth/apis/operations`. Token exchange is `POST /recording_studio_api/apis/operations/oauth/token`. A public token does not work on the ops MCP path, and an operations token does not work on `/recording_studio_mcp`. Public authorize, metadata, and `/recording_studio_mcp` stay as they are.

Oauth's named-API protected-resource registry still advertises only the operations API identifier. Until Oauth also registers `{mcp_mount}/apis/{api_key}` as an MCP identity, omit `resource` on ops authorize and token (blank `resource` is allowed). Public MCP `resource` is already registered and should be sent as today.

Authorization is Recording Studio Accessible through that AccessGrant. Same grant as API. No Pundit. No OAuth scopes.

Custom `show`, `update`, and `delete` handlers, custom capability actions, and registered endpoints that capture `:id` or `:recording_id` run through `RecordingStudioApi::HandlerGuard` before the handler. A blank id, a foreign root, the wrong recordable type, a trashed record, and a role that is too low all return the same tool error: `Resource was not found in this API scope`. The handler does not run. `owns_scoping` on a read, and an endpoint with `scope_id: false`, still call the handler with `recording` nil. Built-in list, show, update, delete, and built-in capability actions keep the accessible-recordings lookup. MCP has no nested tools, so `parent_recording` stays nil.

`tools/list` advertises the tools the host included on that named API's MCP server. Tools are opt-in. `describe` is always present.

Register copy and membership in the gem, then include tools on a host server. Dispatch uses `RecordingStudioApi.lookup` for the handler, input contract, output schema, sensitive flag, and API membership. Authorization stays in that handler and Accessible.

```ruby
RecordingStudioMcp.register_tool(
  name: "ping",
  endpoint: :ping,
  title: "Ping",
  description: "Confirm this named API can reach a registered endpoint.",
  input: {},
  output: "ok"
)
RecordingStudioMcp.register_type(
  type: "Page",
  description: "A page under a folder or workspace. Call describe before you write."
)
RecordingStudioMcp.register_skill(
  name: "page-desk",
  type: "Page",
  title: "Page desk",
  description: "Read and update Page records on this server.",
  body: "Use list with type Page, then show. Writes need parent_id for create.",
  tools: %w[list show create update describe]
)
RecordingStudioMcp.register_server(:public, api: :public) do
  include_tools :list, :show, :create, :update, :ping
  include_tool :secret_metric, allow_sensitive: true
  include_skills "page-desk"
end
```

This is the locked `register_tool` / `register_type` shape other gems copy. Do not add keys for parents, writable fields, or actions. Those come from Recording Studio API and Recording Studio declarations when `describe` runs.

`register_tool`:

- `name` — MCP tool name
- `title` — short label
- `description` — what the tool does, for people and agents. No Access wording. Audience values stay in this text, not an enum
- `type` — optional recordable type when the tool is typed. Use the class name on the named API. Named `Type--*` operation tools map that class through the public-name catalog the same way generic `create` / `show` do.
- exactly one of `operation`, `action`, or `endpoint` — the lookup target
- `input` — copy overlay only (descriptions and examples). Required, type, and allow-blank stay on the API contract
- `output` — short result phrase

`register_type`:

- `type` — recordable type name
- `description` — type paragraph for people and agents. No Access wording

`list`, `show`, `create`, `update`, `delete`, and `capability_action` are includable generic tools. Re-registering a tool name overrides title, description, and input copy only. Type, target, required, and non-empty rules stay on the API contract. MCP text may only describe or narrow inputs. A host override that changes type or target raises at boot.

`describe` lists the types, tools, and skills that server includes. It also returns `parent` (`root`, `allowed_parent_types`; `null` when there are no parent rules), `writable_fields` (name, required, type, allowed values, description), and `capability_actions` when that server includes `capability_action`. Type paragraphs come from `register_type`. Field types, enums, parents, and actions come from the API registration and Recording Studio. Docs type sections use that same `describe` payload.

Boot raises when a tool, type, field, or skill names something the API does not have, when a sensitive item is included without `allow_sensitive`, when an override changes a target, or when an included catalog metric is outside `catalog_metric_resources`. Run `rake recording_studio_mcp:audit` in host CI to print each server's tools and sensitive flags.

Catalogs are built at boot. `tools/list` descriptions stay short. Each session sees the tools on its named API, then filtered by grant role. Dispatch rejects a tool that is not on that session's server. Copy is reviewed code, not runtime input.

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

`register_event("recording updated")` with no block is the built-in trigger for every recordable type. That same registration is the `recording.updated` MCP Event (filter `recording_id`) when `config.events_enabled` is true. In this release only `recording.updated` is fully supported as an MCP Event.

ChatGPT can subscribe with `events/list`, `events/subscribe`, and `events/unsubscribe` on the same authenticated MCP endpoint. Deliveries are signed Standard Webhooks POSTs. SSE progress, `resources/subscribe`, and `notifications/resources/updated` stay as they are. Hosts add more events with `event.webhook_event(name, description:, arguments:, payload:)`.

```ruby
RecordingStudioMcp.configure do |config|
  config.events_enabled = true
  # config.event_subscription_ttl = 24.hours
  # config.event_subscriptions_per_principal = 50
  # config.event_callback_host_allowed = ->(host) { host.end_with?(".example") }
end
```

Run `bin/rails generate recording_studio_mcp:migrations` and `bin/rails db:migrate` so `recording_studio_mcp_event_subscriptions` exists. Configure Active Record encryption keys before setting `config.events_enabled = true`; callback secrets are encrypted.

Accessible recordings are MCP resources at `recording://{id}`. `resources/list`, `resources/read`, and `resources/templates/list` use the same AccessGrant as tools. `resources/list` returns recordings in `id` order, 100 per page. `config.resources_page_size` changes the page size. A page with more recordings includes `nextCursor`. The last page leaves it out. The cursor is opaque. Send it back as `cursor` to read the next page. A malformed cursor is JSON-RPC `-32602`, and the error does not include the cursor. Each page loads that grant's accessible recordings again and keeps rows after the cursor id, so a cursor cannot reveal a recording outside the grant. Recordables are loaded for the recordings on that page. Skill files (`skill://…`) and MCP UI widgets (`ui://…`) are included on the first page. Later pages are recordings only. `resources/read` and `resources/templates/list` are unchanged. `resources/templates/list` still rejects a cursor. Subscribe uses the same access check. The update notification carries the URI only.

A saved change (`record!`, `revise`, `log_event!`) on a subscribed recording is delivered **after commit**. Live SSE connections stay in the web process. Listeners share one Accessible scope check for that dispatch when each grant has already built its scope and the whole prime-time snapshot matches, including the parent recording, role, owner, and whether that snapshot is revoked or trashed. A grant that has not built its scope is checked on its own. A trashed or revoked snapshot is refused and is not reused. The next save checks again. The listening stream's own writer drains the queue. A slow or dead subscriber is dropped (bounded queue + write timeout). The save request does not write sockets.

Webhook subscriptions are enqueued on that save. The job arguments are the subscription id, the recording id, and the event id. The request does not build the JSON body. `DeliverEventWebhookJob` loads the subscription and the grant again, runs the same Accessible scope, and only then builds the body and posts. Delivery is at-least-once. A retried job posts again with the same webhook-id, and the access check runs again on that attempt. A missing subscription, a revoked grant, or a trashed grant is not delivered.

Subscriptions are process-local. On Postgres, MCP fans out `LISTEN`/`NOTIFY` with the event name and recording id. Each process re-checks access for its local subscribers, once per access grant. Other databases stay in-process: a save on worker B does not reach a subscriber on worker A.

`tools/call` does not need `Mcp-Session-Id`. Initialize on `2025-03-26`, `2025-06-18`, and `2025-11-25` returns that header so a GET SSE listen can find the in-memory connection. The store is per process. A worker restart, a second Puma worker, or a proxy that drops the GET stream drops listen state. `2026-07-28` initialize does not open a session. Connector drops during ordinary tool calls are not this store.

The Postgres LISTEN thread starts only in server or worker processes. It does not start in `rails console`, `rails runner`, or Rake tasks (including `db:migrate`). Set `RECORDING_STUDIO_MCP_POSTGRES_BUS=1` to force it on in those processes, or `RECORDING_STUDIO_MCP_POSTGRES_BUS=0` to keep it off in a server. On process exit the bus stops the thread and releases its connection before ActiveRecord tears down the pool (skipped in forked children). Dropped LISTEN connections log and reconnect with bounded backoff until `stop!`.

Tree hosts register types with `register_type` and include generic tools on `register_server`. Included generic tools are then filtered by the access grant's role: `list` when a type enables `index`, `show` when a type enables `show`, `create` when a type enables `create`, `update` when a type enables `update`, `delete` when a type enables `destroy`, and `capability_action` when a type lists a registered capability action the grant's role can run. `index` and `show` need `:view`. `create`, `update`, and `destroy` need `:edit`. A view grant does not see write tools. A grant whose access row is gone (`role` nil) sees no tree read or write tools. `describe` is always listed. Endpoint tools list only when the host included them. Grants that do not report a role keep the included surface for that named API. Each tool's `type` enum is the types that allow that operation. `describe` and `capability_action` still list every registered type. Call `describe` for the type paragraph, included tools, skills, relationships, allowed parents, writable fields, and available actions. Docs pages still list operations, writable field names, sortable fields, required fields, allowed values, output keys, extra fields, allowed children, enabled capability action input contracts, and parent rules. The `type` enum, that describe output, docs tool names, allowed-type errors, and resource reads use a short public name. `RecordingStudioPresskits::PressKit` shows as `PressKit`, so a docs action is `PressKit--set_embargo` and `capability_action` takes `type: PressKit`. MCP reads `registration.public_name`. Tool results use that public name for `type` and `recordable_type`, including `records` rows and nested records. An unregistered type string stays as the API sent it. An untitled resource name is the public name, a space, and the recording id. A blank `public_name:` is the class name without its namespace, because API stores that string. Tree tools accept that public name. A full class name such as `RecordingStudioPresskits::PressKit` is rejected, and the unknown-type error lists the allowed public names. Callers must send the public name. A resource name resolves only when it is that same public name, so `press_kits` does not select `PressKit`. Public and operations APIs keep separate maps. API raises `ConfigurationError` at boot when two types on one named API share a public name. Unknown type or action errors name the allowed set. Domain failures that the dispatcher maps (`RecordingStudioApi` tool errors, `ActiveRecord::RecordInvalid`, `RecordingStudio::AuthorizationError`, `RecordingStudio::ActorRequired`, `RecordingStudio::InvalidParent`, `RecordingStudio::Denial`) return a tool result with `isError`. Actor failures say actor is required. Parent failures name `parent_id`. A plan denial uses `RecordingStudioApi::BillingDenial.interpret` when the code is registered. When the error already has `details` (field names, `parent_id`), that payload is on `structuredContent.details`. Other `StandardError`s stay JSON-RPC `-32603`. Initialize instructions name only the tools that `tools/list` advertises. Records nest by `parent_id`. `root_id` is the workspace, not the parent record. When `list` advertises `parent_id`, walk down with that argument, then `show`. Builtin API index does not filter by `parent_id`. Hosts that run Presskits or Support set `config.list_parent_id_types` to those index types.

`operations: []` is blank, so the API normalizes it to `index`, `show`, `create`, `update`, and `destroy`. MCP then treats `destroy` as allowed for that type when `delete` is included. On the public API, `operations: nil` takes that same path. On a named API, `operations: nil` follows `default_access`. Read-only (the named-API default) stores `index` and `show`, so included `delete` still does not advertise for those types. Read-write stores all five. `operations: []` is not `nil`, so a read-only named API still expands it to all five.

When `RecordingStudioApi.register_resource_handler` is set for `show`, `update`, or `delete`, MCP scopes the recording with `RecordingStudioApi::HandlerGuard` before the handler runs. A miss returns `Resource was not found in this API scope` and the handler does not run. `index` and `create` stay unscoped. Custom create passes the client `parent_id` with `recording` and `parent_recording` nil, so the handler scopes that parent. A custom capability action runs its input contract only after the guard allows the call. Types without a handler still load through the grant's scoped recordings.

A built-in capability action that returns a recording is serialized with that call's access grant, scoped recordings, and arguments. That is the same grant `show` uses. Fields that depend on the grant are in the tool result.

Create and update send writable fields at the request root (`title`, not `attributes`). `list` accepts `pagination_token` from `meta.next_pagination_token`. It advertises `parent_id` only when `config.list_parent_id_types` names a type that allows index. Hosts that run Presskits or Support set that list. Hosts may set `describe_payload` to a callable that receives the default `describe` hash and returns a replacement.

A second `create` with the same `idempotency_key`, or the same `Idempotency-Key` header, returns the first record and does not create another one. A custom create handler uses `RecordingStudioApi::Idempotency.replay` and compares `RecordingStudioApi::IdempotencyStore.fingerprint` of the method, path, and effective input. The same key with a different input is an error. `capability_action` takes an optional `idempotency_key`, or the same header. A key inside `params` is removed before the action contract and still counts when the argument and the header are absent. An action flagged `creates: true`, or a resource handler flagged `creates: true`, replays through that same API entry and the same fingerprint. The same key and the same input return the first result and do not create another record. A new key runs the action again. The same key with different input returns a tool error, code `idempotency_key_reused`, message `Idempotency key already used with different parameters`. `idempotency_key` and a stripped `authorized_by` are left out of the fingerprint. A stored result with no fingerprint still replays. The fingerprint is not written to usage logs. An action that is not flagged ignores the key. A different action or record is a separate replay. It runs. Public and operations tokens do not share stored results. Tool results use the registered public name for `type` and `recordable_type`. An unregistered value that contains `::` shows its last segment, such as `Attachment` or `Location`. Nested items such as attachments and locations are managed through the parent type's actions (for example `add_image`), not as their own types. `describe` says that in `nesting`. Any other unregistered string stays as the API sent it. Callers send the public name. A name that is not registered is an unknown type error.

The `create` input schema keeps `type`, `parent_id`, and `idempotency_key`. `type` is the only top-level required argument. Each creatable type that has required fields adds an `allOf` branch. Its `if` matches `type`. Its `then` lists that type's required fields. That branch lists the required fields from the same field list `describe` uses. Other writable fields stay allowed. A writable field keeps nested schema from its declaration, including `properties`, `items`, `additionalProperties`, `required`, and `examples`. `describe` returns that schema on the field. Create lists it on required fields and on optional fields that declare nested schema. Update lists it on writable fields that declare nested schema.

Catalog-only hosts register `RecordingStudioApi.register_endpoint` routes, then `RecordingStudioMcp.register_tool` with `endpoint:`, and include those names on `register_server` with no generic tree tools. They get `describe` plus the included endpoint tools. Path tokens, OpenAPI query parameters, and `input_contract` fields become `inputSchema` arguments. An endpoint that omits those, such as a Users write route with only a summary, advertises no body fields. The handler can still accept them. Put writable fields on `input_contract` in the gem that registers the endpoint.

When RecordingStudio MCP UI is loaded, an endpoint with `ui:` that resolves to a registered widget advertises `_meta.ui.resourceUri` as `ui://…?v=<digest>` of the packaged HTML. The first `resources/list` page and `resources/read` serve that same URI. Later `resources/list` pages do not repeat it. `resources/read` also accepts the bare `ui://` path. A grant sees a widget only when `actions_for_ui` allows it on that named API. Widget buttons call the real API tool name. MCP UI is optional. Without it, tools and resources stay the same.

### File inputs

An endpoint can opt in to top-level file inputs through its openapi metadata. Clients pass a file as `{ download_url, file_id, mime_type?, file_name? }`:

```ruby
RecordingStudioApi.register_endpoint(
  :site_settings_update,
  http_verb: :patch,
  path: "site_settings",
  handler: Update,
  openapi: {
    "x-mcp-file-params": {
      square_logo_file: { nullable: true, description: "Square logo, or null to remove it." }
    }
  }
)
```

`x-mcp-file-params` is a list of field names, or a hash of name => options. `nullable: true` makes the field `["object", "null"]`. `required: true` adds it to `required`. `description` is copied onto the field. Each field's `inputSchema` property is the file object, with `download_url`, `file_id`, `mime_type`, and `file_name` strings, `download_url` and `file_id` required. A declared field replaces any `input_contract` field of the same name in the schema. File fields live only in that schema. They do not add provider-specific `_meta`. Endpoints without the key are unchanged. MCP only describes the input; the endpoint handler downloads `download_url` (temporary) and does its own validation. Only top-level fields are supported.

Mixed hosts include generic tools, metric tool names, and endpoint tools on the same server. Included generic tools are then filtered by the access grant role. An endpoint is advertised only when its name is one MCP tool token (`[A-Za-z][A-Za-z0-9_.-]*`). Names such as `bad name` and `1bad` are skipped. Dotted names such as `presskits.edit` stay. Names that match a tree tool (`list`, `show`, `create`, `update`, `delete`, `capability_action`, `describe`) are skipped too, so `tools/list` still succeeds. A Workspace `ping` endpoint stays a tool when included. The JSON-RPC `ping` method is separate and is not that tool. An endpoint whose name matches a recordable or API metric tool keeps the endpoint. The metric tool is skipped and logged. `tools/list` still succeeds.

Recordable metrics opt in on the named API. MCP does not grow a second registration API, and it does not call `RecordingStudioMetrics::Api.register!` for these tools.

```ruby
RecordingStudioApi.register_recordable_type_api(
  "Folder",
  metrics: %w[folders.total folders.created_over_time]
)
```

The tool name is the metric identifier with its single dot replaced by a hyphen. The result must match `[a-z][a-z0-9_]*-[a-z][a-z0-9_]*` and be at most 64 characters. MCP does not parse the tool name back to the identifier. The call uses the registry name stored on the tool.

| Metric identifier | MCP tool |
| --- | --- |
| `folders.total` | `folders-total` |
| `folders.created_over_time` | `folders-created_over_time` |
| `metric_samples.total` | `metric_samples-total` |

Each tool's arguments are that metric's registry parameters. A plain count has the list filters only. A timeseries adds `from`, `to`, `interval`, and `group_by`, and those last two keep the catalog enum. `start` and `start_at` are accepted as aliases of `from` when `from` is a parameter. `end` and `end_at` are accepted as aliases of `to` when `to` is a parameter. List filters are one `filter` object whose keys are attribute names (`{ "name": "Ada" }`). That object is what the API reads as `params[:filter]`. A literal `filter[name]` argument is rejected. An unknown filter key comes back as the API error `Unknown filters: ...`. When any recordable metric tool is advertised, initialize adds one sentence telling clients to pass list filters as that object. When none are advertised, that sentence is absent.

A recordable metric tool is advertised only when the host included it, that type enables index, and the access grant can view its scope. A guest does not see these tools. A delegated token returns 401 `invalid_token` when its Access row is deleted or its access recording is trashed. A client-credentials token whose Access row is deleted, while the access recording is still there, still authenticates. The role is nil, so these tools stay off `tools/list`, `describe` stays, and tree reads such as `list` do not. Endpoint tools still list. A voided authorization returns 401 `invalid_token`. A metric whose tool name is not a valid hyphenated name is skipped and logged. An unregistered allowlisted name is skipped the same way. The other tools still list.

Site-usage `operations_metrics_index` and `operations_metrics_show` stay registered endpoint tools. Calling a recordable metric tool runs `RecordingStudioApi::Services::ResourceMetrics::Show`, the same authorize-then-filter path as `GET /:resource/metrics/:name`.

Metrics exposed on the named API also become includable read-only tools. The tool name is the identifier with its dot replaced by a hyphen, same rule as a recordable metric tool. Include that hyphenated name on the server. MCP lists included metrics that `RecordingStudioMetrics::Api::DiscoveryHandler` still allows for the current grant, and from definitions exposed on that API when there is no grant. Calling one runs `RecordingStudioMetrics::Api::ExecuteHandler`. Authorization stays in the metric's `api_authorize` and the grant. MCP does not apply the recordable view check to these tools. A metric the grant cannot run is left off `tools/list`. Calling that name returns `Unknown tool ... Allowed tools: ...`. That hide-on-list behavior is intended.

A timeseries tool takes `from` and `to`. `start` and `start_at` are the same as `from`. `end` and `end_at` are the same as `to`. `interval` is present when the metric has supported intervals. `group_by` is present when the metric has group columns. Metric filters are one `filters` object. The input schema sets `additionalProperties` to false. Unknown arguments return a tool error instead of being ignored.

`config.catalog_metric_resources` limits which resources get these tools. Leave it unset and every metric exposed on the named API may be included by name. Set it to a list of resource names, such as `%w[users]`, to advertise only those. An empty list advertises none. Including a catalog metric the allowlist excludes fails at boot. `operations_metrics_index` and `operations_metrics_show` stay either way.

```ruby
config.catalog_metric_resources = %w[mcp_calls]
```

Tree tools stay parameterized over the recordable tree. They are not one MCP tool per OpenAPI path. Registered endpoints are a different registry. Each one is its own tool.

Tool results include MCP `structuredContent`. The initialize `instructions` match the grant's surface. Hosts may set `instructions_suffix`. It is shown under Guides. On the docs page the callable receives no grant. Initialize `instructions` and the docs Overview are the same text for that surface. The tool list is not refreshed on its own. Tools include display titles. Annotations mark reads, writes, retries (`idempotentHint`), closed Studio scope (`openWorldHint: false`), and GET versus mutating endpoint verbs. `capability_action` is `readOnlyHint: false` and `destructiveHint: true` even when the only enabled action is a view-only `ping`. The server reports `tools.listChanged: false`. Call `tools/list` again when you need a fresh list.

Handlers call the same API resource actions, capability actions, and registered endpoint handlers. MCP does not serve records when API access is disabled.

Staff register the client in Oauth. There is no Dynamic Client Registration.

## Skills

Domain gems own the `SKILL.md` files. They register those files as candidates. `RecordingStudioMcp` keeps the registry and speaks MCP. It chooses which registered skills the current client may see. The client sees that filtered set.

Registering a skill stores a candidate. Exposure is a separate decision.

A domain gem registers the file it ships.

```ruby
RecordingStudioMcp.register_skill(
  name: "research-publications",
  path: RecordingStudioPublications::Engine.root.join(
    "skills/research-publications/SKILL.md"
  )
)
```

`available_if` is optional. Leave it out and the skill is available. The proc receives the current `access_grant` and allows the skill only when it returns `true`.

```ruby
RecordingStudioMcp.register_skill(
  name: "research-publications",
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

1. Add the gem. Pin Recording Studio `>= 7.0, < 8.0` (development tag `v7.8.0`; API 1.21.3 needs `>= 7.7`), API `>= 1.21.3, < 2.0` (git tag `v1.21.3`), Oauth `>= 0.22.0, < 1.0` (development tag `v0.26.0`), Accessible `>= 0.50.0, < 2.0` (development tag `v0.58.0`), Cache `v0.8.0`, Admin `>= 2.19.0, < 3.0` (development tag `v2.20.0`; API 1.21.3 needs `>= 2.19`), Site Settings `v0.7.0`, Attachable `v0.34.0`, Trashable `v1.3.0` (`require: false`), Moveable `v6.1.0`, Icons `v0.5.0`, Metrics `>= 0.9.0, < 1.0` (git tag `v0.10.0`), Logs `>= 0.8.0, < 1.0` (git tag `v0.9.0`), and Flatpack `v0.2.0`. Dummy also pins Root Switchable `v0.17.0`. Add `config/recording_studio_api.yml`. API 1.21.3 loads that file at boot. MCP UI is optional and is not a gemspec dependency. Hosts that want widgets pin `recording_studio_mcp_ui` to tag `v0.4.1`. Then pass `ui:` on the API operation and register the widget in MCP UI. Nothing else to wire.
2. Install and mount API and Oauth first. Allow `RecordingStudioOauth::OauthAuthorization` in Accessible `access_actor_types`.
3. Run `bin/rails generate recording_studio_mcp:install`.
4. Draw Oauth origin well-known: `RecordingStudioOauth::ProtectedResourceRegistry.draw_origin_well_known(self)`. Draw named-API MCP metadata first: `RecordingStudioMcp.draw_named_api_well_known(self)`. Or alias `/.well-known/oauth-protected-resource/recording_studio_mcp` to MCP's metadata controller. ChatGPT and API clients keep using `/recording_studio_oauth/.well-known/oauth-protected-resource`.
5. Register a public PKCE OauthClient for the MCP app. People Connect. Then call MCP with the issued Bearer token. For staff/ops MCP, register an operations OauthClient (`api_key: "operations"`) and Connect at `/recording_studio_oauth/apis/operations/oauth/authorize`. Point the client at `/recording_studio_mcp/apis/operations`.
6. Mount live MCP docs for a named API. The gem owns the controller and views. The host owns the path and the gate. Every MCP docs route shares one `documentation_enabled` flag and one `documentation_access` gate.

```ruby
recording_studio_mcp_docs_for :operations,
  at: "/admin/operations-api/mcp-docs",
  as: :operations_api_mcp_docs
recording_studio_mcp_docs_for :public,
  at: "/admin/public-api/mcp-docs",
  as: :public_api_mcp_docs

RecordingStudioMcp.configure do |config|
  config.documentation_enabled = true
  config.documentation_layout_name = "recording_studio/default_layout"
  config.documentation_access = lambda do |controller:, actor:, api:|
    FeaturedIn::AdminRootDocumentationAccess.allowed?(
      controller: controller,
      actor: actor,
      api: api
    )
  end
end
```

`documentation_access` is `:public`, `:authenticated`, or a callable. Missing actor is `401`. A signed-in actor the callable rejects is `403`. Disabled docs are `404`. The gem does not call Accessible. Once the host gate allows the request, the page shows that named API's full tool list, the same way Scalar shows the full OpenAPI document. It is not filtered to `tools/list` for a grant.

Or generate the same routes:

```sh
bin/rails generate recording_studio_mcp:mcp_docs operations_api \
  --mount-path=/admin/operations-api/mcp-docs \
  --api-surface=operations \
  --layout=recording_studio/default_layout
```

After boot, this engine writes `RecordingStudioOauth.configuration.mcp_mount_path` to MCP's own mount path (`ProtectedResourceMetadata.mcp_mount_path`, default `/recording_studio_mcp`) so Oauth authorize accepts that MCP resource identity. Named-API MCP identities live at `{mcp_mount_path}/apis/{api_key}`. Change MCP's `mcp_mount_path` if you mount the engine somewhere else. Do not change Oauth for this.

Host authentication stays on the host. Dummy uses Devise. Do not add Users as a dependency of this gem.

This gem ships no end-user product UI. Staff admin is the MCP section when `recording_studio_admin` is mounted. Dummy host chrome may use Flatpack. Oauth owns Connect screens.

## Admin

Staff admin is the MCP admin section. Ops MCP lists `/recording_studio_mcp/apis/operations` and its well-known path, and reminds staff to register ChatGPT and Grok Bot in Registered apps with `api_key: "operations"`. Do not seed those OauthClients. Failing subscriptions sits on its own compact row at the top: the live count of open callbacks that bounced, and it opens a table of those subscriptions. Ops MCP, Failed tools, and Usage stay in the card grid below. The Usage widget charts calls from the last 4 weeks and opens the Usage screen. Failed tools lists `tools/call` failures by name from daily totals and opens Usage filtered to failed `tools/call` rows. Usage lists each call. Date range, group by, and status sit on the screen. Failed and method stay in the filter modal. The Usage chart uses the screen's filtered call list. Registered apps opens Oauth's section. It is not the `/docs/mcp` probe. Public MCP and Workspace stay unchanged.

Each authenticated or failed POST to the MCP endpoint writes one usage log. The row stores the method, the tool or skill name, the status, the duration, and the API client id. It does not store the token or the tool arguments. The usage log table is unpartitioned with a UUID primary key. RecordingStudioLogs registers it (`partition_interval: nil`, 30-day retention, no root column) and aggregates UTC days into the existing `recording_studio_mcp_usage_daily_metrics` table (`mcp/usage_daily`, grouped by method and name, summing stored generated `failed_count` and `rate_limited_count`). Hosts also need Logs run-table migrations. Schedule Logs `AggregationJob` (`aggregate_due!`) and `ReconciliationJob`. An ActiveJob backend must process the `:default` queue (`AggregatePeriodJob` is enqueued per insert). Run `RecordingStudioLogs.backfill!("mcp/usage_daily", from: 29.days.ago.to_date, to: Date.current)` once; it is not a recurring job. Existing daily rows are host-time-zone days; new ones are UTC days. Raw logs are pruned only if the host schedules Logs `RetentionCleanupJob`. Do not schedule Logs partition jobs for this table. Do not schedule `rake recording_studio_mcp:maintain_usage`.

The engine registers `:mcp_calls` with Recording Studio Metrics (`blast_radius: :site`, operations only) on `UsageDailyMetric`. Logs MetricsBridge does not auto-publish that summary: the log has no root column. `api_authorize` uses `RecordingStudioMcp::Api::Access.can_view?` (AdminRoot Accessible `:view`). This gem does not call `RecordingStudioMetrics::Api.register!`. The host registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

Paths on the operations API: `GET /metrics` and `GET /metrics/mcp_calls/:name` (`over_time`, `failed_over_time`, `by_tool`, `failed_by_tool`, `by_method`, `rate_limited`). `GET /metrics/mcp_subscriptions/failing` counts active, unexpired event subscriptions with `failure_count > 0`. Those subscriptions turn inactive after 5 failures in a row.

Endpoint tools take the endpoint's OpenAPI query parameters as arguments with the same names. On MCP, `operations_metrics_show` takes `resource`, `name`, `from`, `to` (or `start`, `end`), `interval`, `group_by`, `timezone`, and `filters`. `operations_metrics_index` takes `filters` (`{ "resource": "mcp_calls" }`). Metrics errors such as a `from`/`start` conflict or an unsupported `group_by` come back as tool errors.

```bash
bin/rails generate recording_studio_mcp:migrations
bin/rails db:migrate
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

## MCP reference docs

Hosts mount **live** docs with `recording_studio_mcp_docs_for`. That page builds an OpenAPI 3.1 document from the host catalog for the named API on each request and renders it with vendored Redoc. Tools and server instructions stay in sync with what the host registered. The Recording resource is not in this document. `resources/list` and `resources/read` are unchanged. There is no committed snapshot. The Redoc sidebar lists each tool tag once. `Overview` is first, then the remaining tags in alphabetical order. `Other tools` is last. There is no Core group and no Tools group. Ping and the general tools sit under Overview. Tags are not wrapped in Endpoints, Metrics, or Types groups. The sidebar lists exactly the live tools for that named API, the same set `tools/list` returns with no grant. Named `Type--*` tools sit under that type's tag. Generic tree tools sit under Overview. Capability actions without `register_tool` are not sidebar tools. They stay on `capability_action` and in `describe`. Callers may send the public name or the registered class name. `resolve_type!` maps both through the public-name catalog. A type uses its OpenAPI tags. A type with no tags uses its public name, so Workspace access actions sit under Workspace. Untagged types in the same Ruby namespace as a tagged gem type inherit that group. A host `ping` endpoint with no tag sits under Overview. A tool with no owner sits under `Other tools`. Each type's group intro is that type's `describe` payload: the type paragraph, the tools `describe` lists (generic tools scoped to that type, named `Type--action` tools, and registered endpoints), capability action names (with the creates/idempotency_key line when that action creates), parent rules, and relationships. Generic tools use a `Tool:` line with the public type name and arguments from the tool schema. `list` includes `parent_id` only when the surface advertises it. A type that does not list `delete` in `describe` does not list `delete` on the docs page. A type with those tools and no capability action still has the group. A tag with no describe section is left out of the sidebar. Shared tags list each type's describe section, prefixed with the type name. Named live tools keep their registered `inputSchema`. A gem may set `tag_suffix` on a named action's OpenAPI, once for every type or per type in the overlay. The sidebar tag is the type group, a space, and the suffix (`Video` and `Trash` become `Video Trash`). Alphabetical order keeps `Video` before `Video Trash`. `tag_suffix` is not copied onto the operation. Per-type schema components are not on this page. `TypeName` stays for tool input. Tools may advertise `outputSchema`. The page Overview is the initialize `instructions` for that API, with no grant, plus one line: a view-only connection gets the same text minus the Make changes part. `x-mcp.instructions` stays the initialize text without that line.

The spec is `{mount}/openapi.json` behind the same `documentation_enabled` flag and `documentation_access` gate as the page. Without JavaScript, the page lists each tool name and title in that sidebar order and links to `{mount}/openapi.json`. `{mount}/fullscreen` is the same Redoc viewer without the host layout. Redoc loads from `{mount}/redoc.js` in this gem. Nothing is fetched from a CDN. Telemetry is off.

The page includes a small inline `type="module"` script that imports that local bundle. If the host sets a Content-Security-Policy, allow that script with a nonce (or `script-src` that covers it). Do not add a CDN `script-src` for Redoc.

JSON HTTP APIs stay on Scalar.

Guides for people connecting a client: [docs/introduction.md](docs/introduction.md), [docs/oauth.md](docs/oauth.md), [docs/cursor.md](docs/cursor.md), [docs/claude-code.md](docs/claude-code.md).

`bin/docs-mcp` writes `docs/example-app.openapi.json` from the dummy app's live public catalog. That file is labelled as the **example dummy app**. Do not serve it as product docs. Open `docs/example-app.html` next to it if you want a static Redoc view of that example.

## Dummy

`test/dummy` on port 3000. Sign in with `admin@admin.com` / `Password`. Seed MCP App is a public OauthClient. Studio Workspace starts Connected. Site name `Studio` comes from Site settings when Connect needs it. Seeds also write sample MCP usage logs for the last 4 weeks. Loading seeds again replaces that sample.

The dummy-only docs page at `/docs/mcp` can mint a real test token, probe MCP, and sample-POST the endpoint. It is not the product.

Dummy credentials (`test/dummy/config/credentials.yml.enc`) are encrypted with the shared RecordingStudio_* development master key. Set `RAILS_MASTER_KEY` or put that key in `test/dummy/config/master.key` (gitignored). Keep the encrypted file; do not generate a per-repo dummy key.

## Version

0.43.4
