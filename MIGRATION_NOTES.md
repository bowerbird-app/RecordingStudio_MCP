# Host pins

Ruby 3.3 or newer. Rails 8.1. Recording Studio `~> 4.2`. API `>= 0.11.0, < 0.15`. Metrics `>= 0.3.0, < 0.6`. Oauth `v0.13.1` or later. Logs `>= 0.5.0, < 0.6` (GitHub tag `v0.5.0`).

## 0.21.0

No MCP summary tables. RecordingStudioLogs registers `recording_studio_mcp_usage_logs` as an unpartitioned UUID table with `retention: :indefinite` and no root column. It does not call `aggregate`. Nightly `rake recording_studio_mcp:maintain_usage` still rebuilds `recording_studio_mcp_usage_daily_metrics` for yesterday and today, then deletes raw logs older than 30 days. Do not schedule Logs partition jobs for this table.

## 0.20.2

No migration. Runtime ranges allow API through 0.14.x and Metrics through 0.5.x. Development pins API `v0.14.1`, Metrics `v0.5.0`, Oauth `v0.13.1`, and Logs `v0.5.0`. Recordable metric tool JSON omits `filters` on API 0.11.2 or later.

## 0.20.1

No migration. MCP admin renders Failing subscriptions as a compact widget so it sits on its own row above Ops MCP, Failed tools, and Usage.

## 0.20.0

No migration. MCP admin widgets read `mcp_subscriptions.failing` and `mcp_calls.failed_by_tool` through `RecordingStudioMetrics::Admin` with site authorization. Failing subscriptions opens `mcp_failing_subscriptions`. Failed tools opens Usage filtered to failed `tools/call` rows. Usage keeps date range, group by, and status inline.

## 0.19.0

No migration. Endpoint tool descriptions prefer OpenAPI `description`, then `summary`, then a sentence from the title and route. `capability_action` and `describe` share the type allowlist of registered actions. A grant with no access row still has `describe` and any endpoint tools. Tree reads and writes stay hidden. `users_create` and `users_update` stay without body fields until Users adds an `input_contract`.

## 0.18.0

No migration. `mcp_calls.failed_by_tool` sums failed `tools/call` requests by tool. `mcp_subscriptions.failing` counts active, unexpired event subscriptions with `failure_count > 0`.

## 0.17.0

Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4`. Metrics exposed on the named API are one read-only MCP tool each, named by replacing the identifier's dot with a hyphen. A timeseries takes `from` and `to`. `start` and `start_at` are described as the same as `start`. `end` and `end_at` are described as the same as `end`. Pass metric filters as a `filters` object. `config.catalog_metric_resources` defaults to every exposed resource. Set a resource list to narrow that. `operations_metrics_index` and `operations_metrics_show` stay endpoint tools.

A metric `api_authorize` denies is left off `tools/list`. A call to that name returns `Unknown tool ... Allowed tools: ...`. That is intended. A delegated token returns 401 `invalid_token` when its Access row is deleted or its access recording is trashed. A client-credentials token whose Access row is deleted, while the access recording is still there, still authenticates. The role is nil, so tree reads, writes, and metric tools stay off `tools/list` and `describe` stays. Endpoint tools still list. A voided authorization returns 401 `invalid_token`.

## 0.16.0

Pin `recording_studio_api` to `>= 0.11.0, < 0.12` and `recording_studio_oauth` to `v0.12.2` or later. Allowlisting metrics on `register_recordable_type_api` advertises one read-only MCP tool per metric when that type enables index and the grant can view its scope. The tool name replaces the identifier's single dot with a hyphen. It must match `[a-z][a-z0-9_]*-[a-z][a-z0-9_]*` and be at most 64 characters. An unknown filter attribute is rejected. No migration.

| Metric identifier | MCP tool |
| --- | --- |
| `folders.total` | `folders-total` |
| `folders.created_over_time` | `folders-created_over_time` |
| `metric_samples.total` | `metric_samples-total` |

List filters are a `filter` object of attribute names. A plain count takes those filters only. A timeseries also takes `from`, `to`, `interval`, and `group_by`. `start` and `start_at` alias `from` when `from` is a parameter. `end` and `end_at` alias `to` when `to` is a parameter. An unknown filter key is rejected with the API error. `operations_metrics_index` and `operations_metrics_show` stay endpoint tools.

## 0.15.0

No migration. Tree `tools/list` is the union of operations registered on that named API, plus `describe`, then filtered by the access grant role. A named API that only registers `index` and `show` advertises `list`, `show`, and `describe`. A view grant does not see `create`, `update`, or `delete`. A delegated token returns 401 `invalid_token` when its Access row is deleted or its access recording is trashed. A client-credentials token whose Access row is deleted, while the access recording is still there, still authenticates. Its role is nil, so tree reads and writes are hidden and `describe` stays. Endpoint tools still list. A voided authorization returns 401 `invalid_token`. `capability_action` appears when a type has an action that role can run. `capability_action` stays `readOnlyHint: false` and `destructiveHint: true` even for a view-only `ping`. Calling an unadvertised tool is an unknown-tool error. Calling an advertised tool for a type that does not enable that operation is still an unsupported-operation error.

`operations: []` is normalized by the API to all five operations, so MCP advertises `delete`. On the public API, `operations: nil` does the same. On a named API, `operations: nil` follows `default_access`: read-only stores `index` and `show` (no `delete`), and read-write stores all five. `operations: []` on a read-only named API still expands to all five.

Endpoint names that are not one MCP tool token, and names that match a tree tool, are left off `tools/list`. `tools/list` still succeeds. A Workspace `ping` endpoint stays a tool. Only a removed built-in `ping` tool is gone. The JSON-RPC `ping` method is unchanged.

`tools/call` with non-object `params` or `arguments` returns JSON-RPC `-32602`. A non-object `filter`, a nested filter value, or a non-numeric `limit` returns a tool error. A nested filter is a filter error, not an invalid pagination token.

## 0.11.0

Pin `recording_studio_api` to git tag `v0.6.11` (`~> 0.6`, `>= 0.6.11`). MCP UI is optional and not a gemspec dependency. Hosts that want widgets pin `recording_studio_mcp_ui` to branch `cursor/mcp-ui-engine-6ec3`. Register `ui:` on the API operation and the widget in MCP UI. Nothing else to wire. Widget buttons call the real API tool name. Widget URIs include `?v=` of the packaged HTML so hosts that cache `ui://` by URI get updates.

## 0.10.0

Pin API `v0.6.9`. MCP calls gem-registered resource handlers the same way the API does, so Support (and similar) types can live outside the OauthClient tree. `delete` appears when a type enables destroy.

## 0.9.1

MCP admin (`:mcp`) shows ops MCP URL and well-known paths. Register ChatGPT and Grok Bot by hand in Registered apps with `api_key: "operations"`. Do not seed those OauthClients. Public MCP and Workspace stay as they are.

## 0.9.0

Ops MCP authorize uses the operations named API. Draw `RecordingStudioMcp.draw_named_api_well_known(self)` before Oauth origin well-known. Public MCP stays at `/recording_studio_mcp` and `/recording_studio_oauth/oauth/authorize`. Ops MCP is `/recording_studio_mcp/apis/operations` and `/recording_studio_oauth/apis/operations/oauth/authorize`. Token exchange is `/recording_studio_api/apis/operations/oauth/token`. `api_key: "operations"` is a named API label, not a secret.

Oauth still does not register MCP on named-API protected-resource registries. Omit `resource` on ops authorize and token until Oauth adds `{mcp_mount}/apis/{api_key}` as an MCP identity. Public MCP `resource` is unchanged.

## 0.8.0

ChatGPT MCP Events (webhook delivery). Generate MCP migrations and migrate (`recording_studio_mcp_event_subscriptions`). Set `config.events_enabled = true`. The first event is `recording.updated` from the existing `register_event("recording updated")` catalog. Optional: `event_subscription_ttl`, `event_subscriptions_per_principal`, `event_callback_host_allowed`. SSE progress and resource notifications stay as they are.

## 0.7.2

Pin API `v0.6.1` and Oauth `v0.6.0`. MCP no longer defines `RecordingStudio::Access.roles`; API 0.6.1 ranks grants through `AccessRoles`. Dummy sets Oauth `config.allow_self_registered_apps = true` so MCP Inspector can register. Hosts that want the same run Oauth migrations and set that flag. Keep `draw_origin_well_known`.

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

Depend on `recording_studio_admin ~> 2.0` (Oauth 0.2 already pulls it in). On the admin root, allow `section :mcp`. On the admin home section, link MCP to `admin_section_path("mcp")`. The section is titled MCP admin. It lists ops MCP URL and well-known paths, reminds staff to register ChatGPT and Grok Bot in Registered apps with `api_key: "operations"` (do not seed those apps), charts usage for the last 4 weeks, links to the Usage screen, and links to Oauth's Registered apps section.

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
- API `v0.6.1`
- Oauth `v0.6.0`
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
