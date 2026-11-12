# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.32.0] - 2026-11-12

### Changed
- `describe` includes each capability action's registered OpenAPI `title` and
  `summary`, plus `description` when set. Blank keys are omitted. The type's
  registered OpenAPI description is on the describe payload when present.
- MCP docs drop per-type schema components and their SCHEMA sidebar entries.
  Action tool pages show the type description after `Runs on a <type>`. The
  same text is the sidebar tag description. `TypeName`, API, describe, and
  tool input schemas stay.

### Upgrade notes
- Bump to `0.32.0`. Previous version is `0.31.2`. No MCP protocol migration.
  Clients that parse `describe` may see new keys (`title`, `summary`,
  `description` on actions, `description` on the type). Docs no longer list
  type SCHEMA pages.

## [0.31.2] - 2026-11-12

### Fixed
- MCP docs convert a capability action's RS_API params definition into a JSON
  Schema `inputSchema` (properties, required, enums, `additionalProperties`
  false when `reject_unknown` is true, `minLength` 1 when `allow_blank` is
  false) by reusing `EndpointSchema.build`. Action pages show a real input
  example and no longer dump the raw params JSON in the description.
- Action tools whose type has no OpenAPI tags inherit the sidebar group from
  other types in the same Ruby namespace, so gem types such as
  `RecordingStudioPresskits::Files` sit under Press Kit instead of the generic
  Tools list. Type SCHEMA tags are unchanged, so ungrouped types stay off the
  schema sidebar.
- Duplicate action titles in the same sidebar group insert the type's human
  label after the verb (`Create Press Kit Upload`). An action OpenAPI `title`
  is used when the owning gem sets one.
- Action tool pages keep `Runs on a <type>` and drop the type's allowed
  operations and writable fields. Type schema pages still list those.

### Upgrade notes
- Bump to `0.31.2`. Previous version is `0.31.1`. No MCP migration. Docs-only.

## [0.31.1] - 2026-11-11

### Fixed
- MCP maps `RecordingStudio::ActorRequired` and `RecordingStudio::InvalidParent` to tool errors (`isError`) instead of JSON-RPC `-32603`. Actor and parent failures keep `error.message`. Tool errors that already respond to `details` (API `InvalidActionInputError`, including parent input) copy that payload onto `structuredContent.details`. Other `StandardError`s still become `-32603`.

### Upgrade notes
- Bump to `0.31.1`. Previous version is `0.31.0`. No MCP migration. Clients that treated a missing actor or a disallowed parent as a protocol internal now see `isError` tool results. Read `structuredContent.details` when present for field names such as `parent_id`.

## [0.31.0] - 2026-11-11

### Changed
- MCP docs list each enabled capability action as its own Redoc tool entry
  (not a SCHEMA) under the type's existing tag. The title is the humanized
  action name. The page opens with the type's core label, then the type class,
  operations, writable fields, the existing `Tool: capability_action` line, and
  the input contract. The action's registered OpenAPI summary is included when
  present. Types with those actions stay in `components.schemas` and keep
  working in the API and MCP. Child and section types (those whose registered
  parent is another non-root recordable) omit `x-tags` so Redoc does not also
  list them as SCHEMA entries. The hide check is `any?` over allowed parents, so
  a type allowed under both a root and a nested parent also loses its sidebar
  schema entry. Top-level types keep their schema sidebar entry and still get
  the action tool entries. Those action tools set `x-mcp-docs-only` and use the
  action's input contract as `inputSchema` when one is present (`{type: object}`
  otherwise). `tools/list` is unchanged.

### Upgrade notes
- Bump to `0.31.0`. Previous version is `0.30.3`. No MCP migration. Docs-only.
  Sidebar capability actions are extra `x-mcp.tools[]` entries named
  `{type}--{action}` with `x-mcp-docs-only: true`. They are documentation, not
  protocol tools. A type allowed under both a root and a nested parent omits
  its SCHEMA sidebar entry, same as a nested-only type.

## [0.30.3] - 2026-11-11

### Changed
- MCP docs type schemas use the core recordable `label` as the Redoc title
  (class name when no label is registered). The schema component key stays the
  class name. The description starts with the type's registered OpenAPI
  description when present, then `Type: \`ClassName\``, allowed operations,
  writable fields, and one short entry per capability action. A single note
  under that list says those actions run through `capability_action`.
- Type sidebar tags use the same OpenAPI `tags` as endpoint tools. Types no
  longer sit under a Types fallback, and they no longer use Scalar
  `openapi.tag.group` as a sidebar name. When a type has a tag group, MCP
  reuses explicit `tags` from endpoints that share that group.

### Upgrade notes
- Bump to `0.30.3`. Previous version is `0.30.2`. No MCP migration. Docs-only.

## [0.30.2] - 2026-11-11

### Fixed
- MCP maps `ActiveRecord::RecordInvalid` (validation messages) and `RecordingStudio::AuthorizationError` (`Not authorized`) to tool errors (`isError`). HTTP Recording Studio API still returns 500 for `RecordingStudio::AuthorizationError`; MCP maps that write-gate denial so it is not a JSON-RPC internal. Builtin create converts `RecordingStudio::InvalidParent` to `InvalidActionInputError` in Recording Studio API, which MCP already maps. Other `StandardError`s stay JSON-RPC `-32603`.
- `describe` and allowed-action lists union the type's explicit `capability_actions` with `RecordingStudioApi.capability_actions_for`, so auto-enabled Accessible actions (`list_access`, `grant_access`, `update_access`, `revoke_access`) match dispatch.
- Endpoint `input_contract` failures include `contract_result.errors` in the tool message (for example `Unknown parameters: foo`).

### Upgrade notes
- Bump to `0.30.2`. Previous version is `0.30.1`. No MCP migration. Clients that treated those domain failures as protocol internals now see `isError` tool results. `describe` may list Accessible access actions that dispatch already allowed. Runtime API is `>= 0.17, < 0.22`. Development and dummy Gemfiles pin API `v0.21.0`, Oauth `v0.21.5`, Moveable `v4.1.0`, and Icons `v0.2.0`. API `write_actor` is `AccessGrant#actor`; delegated OAuth writes may record the Accessible grant actor and set the OAuth client as impersonator.

## [0.30.1] - 2026-11-11

### Changed
- MCP docs place each registered type, and its capability actions, under their
  API tag group (`openapi: { tag: { group: ... } }`). Types with no tag stay
  under Types. Tags still appear once. There is no default `x-tagGroups`.
- Each capability action docs entry notes that it is a capability action: call
  it through the `capability_action` tool with the type and action name.
  `describe` lists it at runtime.

### Upgrade notes
- Bump to `0.30.1`. Previous version is `0.30.0`. No MCP migration. Docs-only.
  Sidebar type entries may move from Types to their API tag group.

## [0.30.0] - 2026-11-11

### Changed
- MCP docs no longer wrap tool tags in Redoc `x-tagGroups` (`Core`,
  `Endpoints`, `Metrics`, `Types`). Each tag is a top-level sidebar section and
  appears once. The `tags` list and descriptions are unchanged. Tag order
  follows `x-mcp.tools[]` plus Types. A host
  that sets `tag_groups` on the docs page still gets those groups.

### Upgrade notes
- Bump to `0.30.0`. No MCP migration. The docs sidebar no longer groups tags
  under Core / Endpoints / Metrics / Types. Tool `tags` on `x-mcp.tools[]` are
  the same. If you relied on default `x-tagGroups`, drop that or set
  `tag_groups` on the documentation page.

## [0.29.0] - 2026-11-11

### Added
- MCP docs group tools in the Redoc sidebar. Each docs `x-mcp.tools[]` entry has
  `tags`. Tags stay out of the protocol `tools/list` payload. Tree tools use
  `Core`. Endpoint tools reuse `RecordingStudioApi` `openapi[:tags]` (default
  `Endpoints`). Metric tools named `<group>-<metric>` use a humanized prefix
  (`ai_runs` → `AI Runs`). The spec emits matching top-level `tags` and
  `x-tagGroups` (`Core`, `Endpoints`, `Metrics`, `Types`).
- Type schemas list allowed operations, writable fields, and enabled capability
  actions with input contracts from `describe`, so Public docs show PressKit
  actions without a `describe` call.
- Tree, metric, and (when present) endpoint tools advertise optional MCP
  `outputSchema` on `tools/list` and in the docs entry. Endpoint `outputSchema`
  is a 2xx `application/json` object schema only.
- The mounted docs overview (`info.description`) is human Markdown with sections
  that match the page's tool surface. Agent `instructions` stay on `x-mcp.instructions`.

### Upgrade notes
- Bump to `0.29.0`. No MCP migration. `outputSchema` is an optional MCP Tool
  field on `tools/list`. Docs `tags` are optional and additive. Docs consumers
  that treated `info.description` as initialize instructions should read
  `x-mcp.instructions` instead. Endpoint tools only get `outputSchema` when the
  endpoint's registered `openapi` already carries a 2xx `application/json`
  object schema. `register_endpoint` has no dedicated response-schema argument;
  that stays an API gem decision.

## [0.28.0] - 2026-11-10

### Added
- Mounted MCP docs include a **Full width** control in `recording_studio_page_nav_right`, matching Scalar. `{mount}/fullscreen` renders Redoc on a bare HTML page with no host layout. Same `documentation_enabled` flag and `documentation_access` gate as `show`.

### Changed
- The hosted docs page uses the Scalar wrapper (`mx-auto flex w-full max-w-6xl flex-col gap-6`) with a title and subtitle. Redoc markup lives in a shared partial.

### Upgrade notes
- Bump to `0.28.0`. No MCP migration. Existing `recording_studio_mcp_docs_for` mounts pick up `{mount}/fullscreen`. No host route change.

## [0.27.0] - 2026-11-10

### Added
- `list` advertises `parent_id` when `config.list_parent_id_types` names a type
  that allows index on this named API. Builtin API index does not filter by
  `parent_id`. Hosts that run Presskits or Support set the config.
- Initialize tree instructions explain that records nest by `parent_id`, that
  `root_id` is the workspace (not the parent record), and that `describe` shows
  allowed children and actions. When `list` advertises `parent_id`, they also
  say to walk down with `list` then `show`.
- `describe` includes `output_keys`, extra `fields`, `relationships`, and
  `allowed_children` from the named API resource registry.
- Hosts and gems may set `config.describe_payload` to a callable that receives
  the default describe hash plus `type:`, `registration:`, and `access_grant:`,
  and returns a replacement hash.

### Changed
- `resolve_type!` accepts an unambiguous short type label (the demodulized name
  list envelopes return, such as `PressKit`) in addition to the full constant
  and the resource name. An ambiguous short label returns an error that lists
  the matching full type names.

### Upgrade notes
- Bump to `0.27.0`. No MCP migration. `list` includes `parent_id` only for
  types listed in `config.list_parent_id_types` that also allow index. Short
  type labels work on tree tools. To extend `describe` per type, set
  `describe_payload` in MCP config. Return a hash. Unknown return values keep
  the default payload.

## [0.26.1] - 2026-11-10

### Changed
- OpenAPI type schemas keep writable fields on `properties` only. The
  `x-mcp-writable-fields` copy is gone.
- `Documentation::Openapi.servers` and stringify are private.
- The Redoc vendor host scan flags `http://` as well as `https://` and
  `wss://`. `localhost:4318` stays allowlisted.

### Upgrade notes
- Bump to `0.26.1`. No MCP migration. Spec consumers should read writable
  fields from each type schema's `properties`.


## [0.26.0] - 2026-11-10

### Added
- `Documentation.openapi(api:)` builds an OpenAPI 3.1 document with Redoc's
  `x-mcp` extension from the live named-API catalog.
- `{mount}/openapi.json` and `{mount}/redoc.js` (plus attribution logos) sit
  behind the same `documentation_access` gate as the mounted docs page.

### Changed
- Live MCP docs render with vendored Redoc CE 3.1.0 (MIT). The mounted page
  points Redoc at the live spec. Telemetry is off. Assets are local.
- Removed the Sourcey site, snapshot, and `npx sourcey` docs tooling. Guides
  live under `docs/`. `bin/docs-mcp` exports the dummy app's live spec as an
  example dummy app document. Refresh Redoc with `bin/vendor-redoc 3.1.0`.

### Upgrade notes
- Bump to `0.26.0`. No MCP migration. Keep `recording_studio_mcp_docs_for` and
  `documentation_access`. The page is Redoc pointing at `{mount}/openapi.json`
  and `{mount}/redoc.js`. Hosts that set a CSP need a nonce (or `script-src`)
  for the inline module script on that page. Stop using `docs/mcp` Sourcey
  output.

## [0.25.0] - 2026-11-09

### Added
- Host-mountable live MCP docs. `recording_studio_mcp_docs_for` draws a gem-owned
  page that renders the host catalog for a named API (instructions, tools and
  input schemas, the type enum, `describe` output per type, and `recording://{id}`).
  Access is `documentation_access` (`:public`, `:authenticated`, or a callable
  `|controller:, actor:, api:|`). Every mounted MCP docs route shares that one
  gate and `documentation_enabled`. Once the host allows the request, the page
  shows the full named API tool list, the same as Scalar docs. The gem does not
  filter to `tools/list` per grant and does not add Accessible, Pundit, or a
  second admin. Dummy mounts public and operations docs under
  `/admin/public-api/mcp-docs` and `/admin/operations-api/mcp-docs`.

### Changed
- The Sourcey site under `docs/mcp` stays as the example dummy snapshot. It is
  not the host catalog.

### Upgrade notes
- Bump to `0.25.0`. No MCP migration. Mount live docs with
  `recording_studio_mcp_docs_for` and set `documentation_enabled` plus
  `documentation_access`. featured_in can reuse the same Admin-root callable it
  uses for Scalar. Do not serve the Sourcey snapshot as the product docs.

## [0.24.2] - 2026-11-09

### Added
- Generated MCP reference docs under `docs/mcp` (Sourcey + mcp-parser). The snapshot
  covers this gem's built-in tools only. Host-registered tools stay off the gem
  snapshot. JSON HTTP APIs stay on Scalar. Sourcey is AGPL-3.0 and mcp-parser is
  MIT; both are docs-only `devDependencies` in `docs/mcp/package.json`.

### Upgrade notes
- Bump to `0.24.2`. No MCP migration. No new public API. Docs and tooling only.
  Refresh the snapshot with `bin/docs-mcp`. Do not add Sourcey to a host Gemfile.

## [0.24.1] - 2026-11-05

### Changed
- Dummy `config.authorize_write` allows a write when an actor is present, matching
  Recording Studio 6.5.0 fail-closed writes. Dummy seeds and write tests pass an actor.

### Upgrade notes
- Bump to `0.24.1`. No MCP migration. No new public API. This gem's library still does
  not write through core. Hosts on Recording Studio 6.5.0 need `config.authorize_write`
  and an actor (argument or `config.actor`). Dummy already sets both.

## [0.24.0] - 2026-11-05

### Changed
- Development and dummy Gemfiles pin Recording Studio `v6.3.0`, Flatpack `v0.1.341`, Accessible `v0.24.1`, Admin `v2.5.1`, API `v0.17.1`, Trashable `v0.12.2`, Metrics `v0.7.2`, Oauth `v0.21.0`, Cache `v0.6.2`, Logs `v0.7.3`, Site Settings `v0.5.2`, Attachable `v0.22.0`, and Root Switchable `v0.11.5` (dummy). Runtime still requires Recording Studio `>= 6.1.0` and API `>= 0.17, < 0.18`. Runtime Admin is `>= 2.0`. API `0.18.x` stays out: Oauth `v0.21.0` still caps API below `0.18`.
- Development and dummy lockfiles use Rails `8.1.4.1`. Root lock also uses `bcrypt >= 3.1.22`, `devise >= 5.0.4`, and Puma `8.0.2`.
- Unexpected JSON-RPC failures return a generic internal error. The exception stays in the server log.
- Removed leftover `MIGRATION_NOTES.md` and the dummy `gem_template` credentials assertion.

### Upgrade notes
- Bump to `0.24.0`. No MCP migration.
- Pin Oauth `v0.21.0` and follow its Accessible and Admin notes. Keep API on `>= 0.17, < 0.18` (git tag `v0.17.1`) until Oauth allows `0.18.x`.
- Pin Recording Studio `v6.3.0` in development (runtime floor stays `>= 6.1.0`), Accessible `v0.24.1`, Cache `v0.6.2`, Admin `v2.5.1`, Trashable `v0.12.2`, Metrics `v0.7.2`, Logs `v0.7.3`, Site Settings `v0.5.2`, Attachable `v0.22.0`, Flatpack `v0.1.341`, and dummy Root Switchable `v0.11.5`.
- Hosts on Rails `8.1.4` should move to `8.1.4.1`.

## [0.23.2] - 2026-11-02

### Changed
- Dummy no longer tracks dumped login HTML or an empty makeup-artist keep file.
- Development and dummy lockfiles use `rack` `3.2.8`.

### Upgrade notes
- Bump to `0.23.2`. No MCP migration. No new public API.

## [0.23.1] - 2026-10-27

### Changed
- Runtime requires `recording_studio` `>= 6.1.0` and `recording_studio_api` `>= 0.17, < 0.18`.
- Development and dummy Gemfiles pin Recording Studio `v6.1.0`, Flatpack `v0.1.320`, Accessible `v0.22.1`, Admin `v2.5.1`, API `v0.17.1`, Trashable `v0.12.0`, Metrics `v0.7.0`, Oauth `v0.19.1`, Cache `v0.6.0`, Logs `v0.7.1`, Site Settings `v0.5.2`, Attachable `v0.22.0`, and Root Switchable `v0.11.0` (dummy). Dummy Root Switchable `config.layout` is `"flat_pack_sidebar"`. Dummy copies Oauth `plugin_key`, drops Attachable Library/Placement types, and no longer includes `UsesDefaultLayout`.

### Upgrade notes
- Bump to `0.23.1`. No MCP migration. Hosts need Recording Studio `6.1.0` or later. 4.2 is no longer supported. Run Oauth's `plugin_key` migration when pinning Oauth `v0.19.1`.
- Pin API `>= 0.17, < 0.18` (git tag `v0.17.1`), Oauth `v0.19.1`, Accessible `v0.22.1`, Cache `v0.6.0`, Admin `v2.5.1`, Trashable `v0.12.0`, Metrics `v0.7.0`, Logs `v0.7.1`, Site Settings `v0.5.2`, Attachable `v0.22.0`, and Flatpack `v0.1.320`.

## [0.23.0] - 2026-10-23

### Changed
- Development and dummy Gemfiles pin Logs `v0.7.0` and Metrics `v0.6.1`. Runtime ranges are `recording_studio_logs >= 0.7.0, < 1.0` and `recording_studio_metrics >= 0.3.0, < 1.0`. API stays `>= 0.16, < 0.17`.
- MCP UI is optional and is not a gemspec dependency. Hosts that want widgets pin `recording_studio_mcp_ui` to tag `v0.4.1`.
- Endpoint file inputs keep the `x-mcp-file-params` JSON Schema shape and no longer set `_meta["openai/fileParams"]`. ChatGPT clients that read `_meta["openai/fileParams"]` no longer get those file fields.
- `mcp_calls.*` metrics register on `UsageDailyMetric` through public `RecordingStudioMetrics.register`, with `api_authorize` from `RecordingStudioMcp::Api::Access`. RecordingStudioLogs `mcp/usage_daily` fills that existing table (`period_column :metric_date`, group by method and name, `call_count`, `failed_count`, `rate_limited_count`). Homemade nightly rake and `MaintainUsageJob` are gone. Raw usage logs keep 30-day Logs retention. Each usage log has stored generated `failed_count` and `rate_limited_count` (`1` or `0` from `failed` / `rate_limited`) so Logs can `SUM` those flags on Postgres. Those columns exist only because Logs cannot yet do conditional or boolean-cast sums; drop them once it can. Daily counts rebuild off-request through Logs `AggregatePeriodJob` (`count: :async`).
- Recordable and catalog metric tools share one `MetricTools::Tool` type, one skip logger, and one dispatcher execute path. `CatalogMetricTools` and `RecordableMetricTools` are gone. Skip warnings use one `skipped metric` prefix.
- `Connection#enqueue_updated` is gone. Use `try_enqueue_updated`.
- JSON-RPC lives in `Protocol`. Tree, endpoint, and metric calls live in `Dispatcher`.

### Upgrade notes
- Bump to `0.23.0`. Run MCP migrations. `AddFailedAndRateLimitedCountsToMcpUsageLogs` adds stored generated `failed_count` and `rate_limited_count` on `recording_studio_mcp_usage_logs` only. It does not alter `recording_studio_mcp_usage_daily_metrics` (those columns already exist). Rollback drops the log columns, not daily rows.
- Run Logs migrations (`recording_studio_logs_aggregation_runs` and `recording_studio_logs_maintenance_runs`). Stop scheduling `rake recording_studio_mcp:maintain_usage`. Schedule Logs `AggregationJob` (`aggregate_due!`) and `ReconciliationJob`. An ActiveJob backend must process the `:default` queue (`AggregatePeriodJob` is enqueued per insert). Run `RecordingStudioLogs.backfill!("mcp/usage_daily", from: 29.days.ago.to_date, to: Date.current)` once (it is not recurring). Existing daily rows are host-time-zone days; new aggregation writes UTC days. Raw usage logs are pruned only if the host schedules Logs `RetentionCleanupJob`. Do not drop `recording_studio_mcp_usage_daily_metrics`.
- Pin Logs `>= 0.7.0, < 1.0` (development tag `v0.7.0`) and Metrics `v0.6.1`. Hosts that want widgets pin MCP UI `v0.4.1`.
- After boot, MCP still writes `RecordingStudioOauth.configuration.mcp_mount_path`. Set MCP's mount if the engine is not at `/recording_studio_mcp`. Do not change Oauth for this.
- ChatGPT file inputs that depended on `_meta["openai/fileParams"]` need the `x-mcp-file-params` JSON Schema fields instead.

## [0.22.0] - 2026-10-22

### Added
- An OAuth MCP tool call that writes through `record!`, `revise`, or `log_event!` stores `authorized_by_type` and `authorized_by_id` on that event when the event actor is the OAuth client. Those are the class and raw id of the token's `OauthAuthorization#manager_actor`. Client-supplied copies of those keys are replaced. The event actor stays the OAuth client. `Current.actor` and the impersonator stay unset. A client-credentials call does not add the keys, and client-sent copies are removed on that client's writes. The stamp clears when the tool call ends.
- Runtime requires `recording_studio_api` `>= 0.16, < 0.17`. MCP passes the sign-in `authorized_by` into `AccessGrant` and does not add context constructor keywords. The development lockfile pins API tag `v0.16.0` and Oauth tag `v0.15.1`.

### Upgrade notes
- Bump to `0.22.0`. No migration.
- Hosts that read event metadata will see `authorized_by_type` and `authorized_by_id` on OAuth MCP writes that go through `record!` and whose actor is the OAuth client. The id is the record id. The actor is still the OAuth client.
- Client-credentials writes do not get those keys. Client-sent `authorized_by_*` keys are removed on that client's writes. API `create` does not record an event. API `delete` hard-deletes the recording. RecordingStudio_api v0.16.0's `delete_metadata` builds authorized_by metadata, and `Destroy` does not call it, so a delete still has no event row.
- Hosts need RecordingStudio_api `>= 0.16, < 0.17` and Oauth `v0.15.1` or later.
- Runtime `recording_studio_logs` stays `>= 0.5.0, < 1.0` and `recording_studio_metrics` stays `>= 0.3.0, < 1.0`, as in 0.21.1.

## [0.21.1] - 2026-10-22

### Changed
- Runtime dependency `recording_studio_logs` is `>= 0.5.0, < 1.0` (CI tested with 0.5.0).
- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 1.0` (CI tested with 0.5.0).
- No code change.

### Upgrade notes
- Bump to `0.21.1`. No migration.

## [0.21.0] - 2026-10-20

### Added
- RecordingStudioLogs `>= 0.5.0, < 0.6` registration for MCP usage logs
  (`partition_interval: nil`, UUID primary key, `retention: :indefinite`,
  no root column). Registration does not call `aggregate` and does not
  create summary tables. Recording Studio Metrics still owns `mcp_calls.*`
  on `recording_studio_mcp_usage_daily_metrics`.

### Changed
- Nightly `rake recording_studio_mcp:maintain_usage` still rebuilds the
  legacy daily metrics for yesterday and today, then prunes raw logs older
  than 30 days. Logs `RetentionCleanupJob` does not clean this table.
  Do not schedule Logs partition jobs for it.

### Upgrade notes
- Bump to `0.21.0`. No MCP summary migration.
- Pin `recording_studio_logs` to `>= 0.5.0, < 0.6` (development and dummy
  already pin GitHub tag `v0.5.0`).
- Do not set a Logs aggregation for MCP usage, and do not add
  `config.logs_summaries_enabled`.

## [0.20.2] - 2026-10-20

### Changed
- Runtime dependency `recording_studio_api` is `>= 0.11.0, < 0.15`. Development and dummy Gemfiles pin API `v0.14.1`.
- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 0.6`. Development and dummy Gemfiles pin Metrics `v0.5.0`.
- Development and dummy Gemfiles pin Oauth `v0.13.1` so API `< 0.15` resolves.
- Development and dummy Gemfiles pin Logs `v0.5.0` because API 0.14.x depends on `recording_studio_logs`.

### Upgrade notes
- Bump to `0.20.2`. No migration.
- Pin `recording_studio_api` to `>= 0.11.0, < 0.15` and `recording_studio_metrics` to `>= 0.3.0, < 0.6`. Hosts that want API 0.14.x should pin Oauth `v0.13.1` or later and Logs `v0.5.0`.
- Recordable metric tool results omit `filters` when the host runs API 0.11.2 or later. The key was always `{}`.

## [0.20.1] - 2026-10-20

### Fixed
- MCP admin puts Failing subscriptions on its own compact row at the top. Ops MCP, Failed tools, and Usage stay in the card grid below.

### Upgrade notes
- Bump to `0.20.1`. No migration.

## [0.20.0] - 2026-10-19

### Added
- MCP admin shows failing event subscriptions and failed tool calls from `RecordingStudioMetrics`. Failing subscriptions opens a table of active, unexpired subscriptions with `failure_count > 0`. Failed tools opens Usage with Failed and Method filters. Usage can filter by status, failed, and method. It does not group failures by tool.

### Changed
- Usage keeps date range, group by, and status on the screen. Failed and method stay in the filter modal.

### Upgrade notes
- Bump to `0.20.0`. No migration.

## [0.19.0] - 2026-10-16

### Changed
- Endpoint tool descriptions use OpenAPI `description`, then `summary`, then a sentence from the tool title and the HTTP route. They no longer append a raw `GET users` fragment when human text exists.
- `capability_action` and `describe` use the same list. An action appears when it is registered on the named API, listed on the type, and the grant's role can run it. `describe` no longer hides a listed action just because the recordable mixin check failed.

### Fixed
- README and 0.15 notes said a grant with no access row sees `describe` only. Tree tools hide. `describe` stays. Endpoint tools still list.
- CHANGELOG compare for `0.10.0` pointed at `v0.9.2`. The previous documented release is `0.9.1`.

### Upgrade notes
- Bump to `0.19.0`. No migration.
- Clients that relied on a raw `GET path` suffix in an endpoint description should read the OpenAPI description or summary instead.
- Hosts that listed `capability_actions` without registering the action lose the `capability_action` tool until the action exists on that named API.
- `users_create` and `users_update` still expose no body fields until Recording Studio Users adds an `input_contract` (or OpenAPI query parameters) on those endpoints. MCP does not invent those fields.

## [0.18.0] - 2026-10-15

### Added
- `mcp_calls.failed_by_tool`: failed `tools/call` requests by tool, from the daily usage rollups.
- `mcp_subscriptions.failing`: active, unexpired event subscriptions with `failure_count > 0`.

### Upgrade notes
- Bump to `0.18.0`. No migration.

## [0.17.0] - 2026-10-15

### Added
- One read-only MCP tool per metric exposed on the named API. The call runs `RecordingStudioMetrics::Api::ExecuteHandler`. Listing uses `RecordingStudioMetrics::Api::DiscoveryHandler` for the current grant.
- `config.catalog_metric_resources` limits those tools to named resources. Unset means every exposed metric. `operations_metrics_index` and `operations_metrics_show` stay endpoint tools.

### Changed
- Runtime dependency `recording_studio_metrics` is `>= 0.3.0, < 0.4`.

### Fixed
- A metric `api_authorize` that raises is skipped. `tools/list` still returns the other metrics, and the warning does not include the exception text.
- Period alias descriptions say `Same as start.` and `Same as end.`, matching the HTTP parameters.
- A metric tool whose name collides with an endpoint or another tool is skipped and logged. `tools/list` still succeeds. An allowlisted metric that is not registered is skipped the same way.

### Upgrade notes
- Bump to `0.17.0`. No migration.
- Pin `recording_studio_metrics` to `>= 0.3.0, < 0.4`.
- Set `config.catalog_metric_resources` when the named API should not advertise every exposed metric.

## [0.16.0] - 2026-10-15

### Added
- One read-only MCP tool per recordable metric allowlisted with `metrics:` on `register_recordable_type_api`. The call runs `RecordingStudioApi::Services::ResourceMetrics::Show`.
- Tool names replace the metric identifier's single dot with a hyphen. The result must match `[a-z][a-z0-9_]*-[a-z][a-z0-9_]*` and be at most 64 characters. A name that does not match is skipped and logged. The rest of `tools/list` still returns.
- The tool is advertised only when that type enables index and the access grant can view its scope.
- `start` and `start_at` are accepted as aliases of `from` when the metric has `from`. `end` and `end_at` are accepted as aliases of `to` when the metric has `to`. A plain count does not take a window. Timeseries `interval` and `group_by` keep the catalog enum.

| Metric identifier | MCP tool |
| --- | --- |
| `folders.total` | `folders-total` |
| `folders.created_over_time` | `folders-created_over_time` |
| `metric_samples.total` | `metric_samples-total` |

- List filters are a `filter` object of attribute names. An unknown filter key returns the API error `Unknown filters: ...`. When any of these tools is advertised, initialize adds one sentence about that `filter` object.

### Changed
- Runtime dependency `recording_studio_api` is `>= 0.11.0, < 0.12`.

### Upgrade notes
- Bump to `0.16.0`. No migration.
- Pin `recording_studio_api` to `>= 0.11.0, < 0.12`.
- Pin `recording_studio_oauth` to `v0.12.2` or later.
- Hosts opt in with `metrics:` on the recordable registration. Site-usage `operations_metrics_index` and `operations_metrics_show` stay endpoint tools.

## [0.15.0] - 2026-10-15

### Changed
- Tree tools in `tools/list` follow the union of registered operations on that named API, then the access grant role.
  `list` needs `index` (`:view`), `show` needs `show` (`:view`), `create` needs `create` (`:edit`),
  `update` needs `update` (`:edit`), `delete` needs `destroy` (`:edit`), and `capability_action` appears
  when a type has a capability action that role can run. A delegated token returns 401 `invalid_token`
  when its Access row is deleted or its access recording is trashed. A client-credentials token whose
  Access row is deleted, while the access recording is still there, still authenticates. Its role is nil,
  so tree reads and writes are hidden and `describe` stays. Endpoint tools still list.
  A voided authorization returns 401 `invalid_token`.
  `describe` stays whenever the API has recordable types. Initialize instructions mention only
  those advertised tools. Each tool's `type` enum is the types that allow that operation.
  `tools/call` returns `-32602` for non-object params or arguments. Non-object filters, nested filter
  values, and non-numeric limits return a tool error.
- Endpoint names that are not one MCP tool token, and names that collide with a tree tool, are skipped.
  `tools/list` still succeeds.

### Removed
- The fixed tree tool list that always advertised `create`, `update`, and `capability_action`.

### Upgrade notes
- Bump to `0.15.0`. No migration and no configuration change.
- MCP clients on a named API that only registers `index`/`show` no longer see `create`, `update`,
  or `capability_action` in `tools/list`. Calls to a missing tool still return an unknown-tool error.
  Calls to an advertised tool for a type that does not enable that operation still return the
  existing unsupported-operation error.
- A view grant no longer sees edit tools. A delegated token returns 401 `invalid_token` when its Access row is deleted or its access recording is trashed. A client-credentials token whose Access row is deleted, while the access recording is still there, still authenticates. Its role is nil, so tree reads and writes are hidden and `describe` stays. Endpoint tools still list. A voided authorization returns 401 `invalid_token`.
  `operations: []` still advertises `delete` because the API expands a blank list to all five operations.
  On the public API, `operations: nil` does the same. On a named API, `operations: nil` follows `default_access`.
- Endpoint names that are not a single tool token, or that match a tree tool, are omitted. A registered
  `ping` endpoint is unchanged.

## [0.14.4] - 2026-10-14

### Changed
- Allow `recording_studio_api` `>= 0.6.11, < 0.11` so hosts can run API 0.10.0.
  Development and dummy Gemfiles pin API `v0.10.0` and Oauth `v0.12.1`.

## [0.14.3] - 2026-10-14

### Changed
- Allow `recording_studio_api` `>= 0.6.11, < 0.10` so hosts can run API 0.9.0.
  Development and dummy Gemfiles pin API `v0.9.0` and Oauth `v0.11.1`.

## [0.14.2] - 2026-10-14

### Changed
- Runtime dependency `recording_studio_api` widened to `>= 0.6.11, < 0.9` so hosts can use API `0.8.0` (list `total_count`, metrics aliases). The development Gemfiles pin API tag `v0.8.0` and Oauth tag `v0.10.5` (Oauth 0.10.5 also allows API `< 0.9`). With API 0.8, `start` wins over `from` instead of returning a conflict error; the MCP metrics test now expects that.

### Notes
- The `v0.14.1` tag points at the Accessible `v0.18.0` bump (#45), whose `VERSION` still read `0.14.0`; this API range change ships as `0.14.2`.

### Upgrade notes
- Bump to `0.14.2`. No migration and no configuration change.

## [0.14.0] - 2026-10-14

### Added
- Opt-in file inputs for endpoint tools. An endpoint lists top-level fields in `openapi` under `x-mcp-file-params` (names, or name => `{ nullable:, required:, description: }`). Each one gets the ChatGPT file object schema (`download_url` and `file_id` required, `mime_type` and `file_name` optional; `["object", "null"]` when nullable), and the tool advertises `_meta["openai/fileParams"]`.
- `RecordingStudioMcp::FileParams`.

### Changed
- Endpoint tool `_meta` is merged, so `ui.resourceUri` and `openai/fileParams` can appear together.

### Upgrade notes
- Bump to `0.14.0`. No migration. Endpoints that do not declare `x-mcp-file-params` are unchanged.

## [0.13.1] - 2026-10-13

Allow Recording Studio API 0.7 alongside 0.6.11+.

### Changed
- Runtime dependency `recording_studio_api` from `~> 0.6, >= 0.6.11` to `>= 0.6.11, < 0.8` (GitHub tag `v0.7.0`).
- Runtime dependency `recording_studio_metrics` from `~> 0.3` to `~> 0.2, >= 0.2.2` (API 0.7 needs metrics `>= 0.2.2`; `~> 0.2` still allows Metrics `0.3.x`). Dev pins stay on Metrics `v0.3.0`.
- Pin `recording_studio_oauth` to git tag `v0.10.1` (API constraint widened to `< 0.8`).

### Upgrade notes
- Bump to `0.13.1`. No migration.
- Pin `recording_studio_api` to git tag `v0.7.0` (or keep `>= 0.6.11` and `< 0.8`).
- Pin `recording_studio_oauth` to git tag `v0.10.1` when using API 0.7.
- Keep Metrics at `v0.3.0` (or any `>= 0.2.2` in the `0.2`/`0.3` line).


## [0.13.0] - 2026-10-13

Endpoint tools advertise OpenAPI query parameters, so MCP clients can send Metrics date ranges and grouping.

### Added
- `EndpointSchema` adds each OpenAPI `in: query` parameter of a registered endpoint to the tool `inputSchema` under the same name, with its schema and description. Query `required` flags carry over. Contract fields and path tokens still win on a name collision.
- With Recording Studio Metrics `0.3.0`, `operations_metrics_show` advertises `filters`, `interval`, `start`, `from`, `end`, `to`, `group_by`, and `timezone`, and `operations_metrics_index` advertises `filters` (`filters.resource`). Arguments pass through unchanged to the Metrics handlers. Metrics errors (`InvalidDateRange`, `InvalidGroupBy`, `InvalidFilter`, unknown metric) come back as MCP tool errors.

### Changed
- Runtime dependency `recording_studio_metrics` `~> 0.3` (GitHub tag `v0.3.0`).

### Upgrade notes
- Bump to `0.13.0`. No migration.
- Pin `recording_studio_metrics` at tag `v0.3.0`.

## [0.12.1] - 2026-10-12

Postgres LISTEN bus no longer starts during rake, console, or runner, and shuts down cleanly before connection teardown.

### Fixed
- `PostgresBus` skips auto-start in Rake tasks (including `db:migrate`), `rails console`, and `rails runner`. Runner detection uses `defined?(Rails::Command::RunnerCommand)` (railties loads that class before `boot_application!`; `ARGV` no longer contains `"runner"` by then). Server and worker processes still start as before. Set `RECORDING_STUDIO_MCP_POSTGRES_BUS=1` to force start, or `0` to force off.
- `PostgresBus.stop!` signals the LISTEN loop, wakes it, and joins with a timeout. If the join times out, the listen connection is left for process exit (not released while the thread may still use it). `at_exit` is pid-guarded so forked children (e.g. Solid Queue) do not stop the parent's bus.
- `wait_for_notify` uses a timeout. `IOError`, `PG::Error`, and `ActiveRecord::ActiveRecordError` are logged and reconnect indefinitely with backoff capped at 5s until `stop!`. Attempt counters reset only after a successful wait; warnings are rate-limited. `release_listen_connection` skips `UNLISTEN` on a dead connection so rake exit cannot race into a segfault.

### Upgrade notes
- Bump to `0.12.1`. No migration.
- Hosts that need the bus inside console, runner, or a Rake task must set `RECORDING_STUDIO_MCP_POSTGRES_BUS=1`.


## [0.12.0] - 2026-10-09


Site-wide MCP usage metrics register with Recording Studio Metrics for the
operations API.

### Added
- `RecordingStudioMcp::Metrics.register!` registers `:mcp_calls` on the
  existing `UsageDailyMetric` table (`blast_radius: :site`). Metrics:
  `mcp_calls.over_time` (sum of `call_count` by `metric_date`),
  `mcp_calls.failed_over_time` (sum of `failed_count` by `metric_date`),
  `mcp_calls.by_tool` (sum of `call_count` for `tools/call` by
  `subject_name`), `mcp_calls.by_method` (sum of `call_count` by
  `method_name`), and `mcp_calls.rate_limited` (sum of
  `rate_limited_count`). Each is exposed on `:operations` only.
  `api_authorize` uses `RecordingStudioMcp::Api::Access.can_view?`
  (AdminRoot Accessible `:view`, the same check as the MCP admin section).
- Runtime dependency `recording_studio_metrics` `~> 0.2` (GitHub tag `v0.2.0`).

### Upgrade notes
- Bump to `0.12.0`. No migration. Usage logging is unchanged.
- Add `recording_studio_metrics` at tag `v0.2.0`.
- Keep `recording_studio_api` at tag `v0.6.11` (`~> 0.6`, `>= 0.6.11`, `< 0.7`).
- This gem does not call `RecordingStudioMetrics::Api.register!`. The host
  registers Metrics endpoints once:

```ruby
RecordingStudioMetrics::Api.register!(api: :operations)
```

## [0.11.0] - 2026-10-09

Optional MCP Apps widgets when RecordingStudio MCP UI is loaded.

### Added
- Endpoint tools include MCP Apps `_meta.ui.resourceUri` when `RecordingStudioApi.ui_for` names a widget that `RecordingStudio::MCP_UI.find` resolves. The URI is `ui://…?v=<digest>` of the packaged widget HTML, memoized per process per widget id so hosts that cache `ui://` by URI pick up HTML changes.
- `resources/list` and `resources/read` serve those same versioned `ui://` documents from `RecordingStudio::MCP_UI.package(...).to_mcp_resource`. `resources/read` accepts the versioned URI and the bare one. A grant sees a widget only when `actions_for_ui` finds an action on that grant's named API.
- Tree tools do not get UI meta. `tools/list` skips attach when the tool has no API endpoint name.

### Notes
- MCP UI is optional. This gem does not depend on it. Without that constant, tools and resources stay as they were.
- Widget buttons call the real API tool name. MCP does not dispatch aliases.
- Provider-agnostic MCP Apps metadata only. Clients that cannot load `ui://` still get the structured tool result.
- Requires `recording_studio_api` `>= 0.6.11` (`v0.6.11`). MCP UI is optional: pin `cursor/mcp-ui-engine-6ec3` (PR #1) when you want widgets.

### Upgrade notes
- Bump to `0.11.0`. Pin API `v0.6.11` (`~> 0.6`, `>= 0.6.11`).
- MCP UI is optional. Do not add it unless the host wants widgets.
- Register `ui:` on the API operation and the matching widget in MCP UI. No other wiring.

## [0.10.0] - 2026-10-08

### Added
- Tree tool `delete` when a type on the OauthClient's named API enables `destroy`. It is marked destructive. Types without destroy keep the previous tool list.
- Gem-registered `RecordingStudioApi.resource_handler` dispatch for `list`, `show`, `create`, `update`, `delete`, and `capability_action`. When a handler is registered, MCP skips scoped `load_recording` / authorize and calls the handler the same way Recording Studio API 0.6.9 does (`recording` and `parent_recording` nil, `id` set, handler owns lookup). Non-2xx handler statuses become MCP tool errors.

### Changed
- Require `recording_studio_api ~> 0.6` and `>= 0.6.9` (git tag `v0.6.9`).
- `type` enums stay the named API's `register_recordable_type_api` registry so operations MCP can list Support types that public MCP does not.

### Notes
- Types without a resource handler still use scoped lookup. A record outside the grant still 404s.

### Upgrade notes
- Bump to `0.10.0`. Pin API `v0.6.9`.
- Hosts that register Support (or other) resource handlers get those types on the named API's MCP. Ops clients bound under AdminRoot can list/show/create/update/delete/move Support content that lives under a Workspace.
- Clients see `delete` only when at least one advertised type enables destroy.

## [0.9.1] - 2026-10-07

### Added
- MCP admin (`:mcp`) lists ops MCP connection paths: `/recording_studio_mcp/apis/operations` and `/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations`, plus a hint to register ChatGPT and Grok Bot in Registered apps with `api_key: "operations"`. No OauthClient seeding. Public MCP and Workspace are unchanged.

### Upgrade notes
- Bump to `0.9.1`. Allow `section :mcp` on the admin root if you want the ops connection copy on AdminRoot.

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

## [0.7.2] - 2026-10-06

### Changed
- Pin `recording_studio_oauth` to git tag `v0.6.0` (`~> 0.6`).
- Pin `recording_studio_api` to git tag `v0.6.1` (`~> 0.6.1`).
- Remove the temporary `RecordingStudio::Access.roles` shim. API 0.6.1 ranks grants through `AccessRoles` (Accessible 0.11).

### Notes
- Dummy turns on Oauth self-registered apps (`config.allow_self_registered_apps = true`) so MCP Inspector can RFC 7591 register after RFC 8414 discovery. Hosts stay off until they set the same flag and run Oauth migrations.

### Upgrade notes
- Bump to `0.7.2`. Pin Oauth `v0.6.0` and API `v0.6.1`.
- Run `bin/rails generate recording_studio_oauth:migrations` and `bin/rails db:migrate`.
- To let MCP Inspector self-register, set `config.allow_self_registered_apps = true` in the Oauth initializer. Keep `draw_origin_well_known`.

## [0.7.1] - 2026-10-05

### Fixed
- `server/discover` now returns the MCP `2026-07-28` DiscoverResult: `resultType`, `supportedVersions` (the four versions this endpoint speaks), the same `capabilities` as initialize, grant-aware `instructions`, `ttlMs` / `cacheScope`, and `serverInfo` under result `_meta["io.modelcontextprotocol/serverInfo"]`. ChatGPT (`openai-mcp`) was stopping after discover because the old body had only `protocolVersions` and top-level `serverInfo`, so it never called `tools/list`.
- Modern `tools/list` is a cacheable complete result. Modern `ping` and `tools/call` include `resultType` (CallToolResult is not cacheable). `tools/call` without a name is `-32602`.
- `MCP-Protocol-Version` that disagrees with `params._meta["io.modelcontextprotocol/protocolVersion"]` is JSON-RPC `-32020` with HTTP 400. A missing header still falls back to that `_meta` version, then to `2025-03-26`.

### Notes
- `supportedVersions` lists every version this server speaks, including legacy initialize revisions. Discover itself is always the `2026-07-28` result shape.
- Oauth pin is unchanged.

### Upgrade notes
- Bump to `0.7.1`. No host config change. Clients that call `server/discover` then `tools/list` (ChatGPT) now see tools.

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.32.0...HEAD
[0.32.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.31.2...v0.32.0
[0.31.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.31.1...v0.31.2
[0.31.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.31.0...v0.31.1
[0.31.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.30.3...v0.31.0
[0.30.3]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.30.2...v0.30.3
[0.30.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.30.1...v0.30.2
[0.30.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.26.1...v0.27.0
[0.26.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.26.0...v0.26.1

[0.26.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.25.0...v0.26.0
[0.25.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.24.2...v0.25.0
[0.24.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.24.1...v0.24.2
[0.24.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.21.1...v0.22.0
[0.21.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.21.0...v0.21.1
[0.21.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.20.2...v0.21.0
[0.20.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.20.1...v0.20.2
[0.20.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.20.0...v0.20.1
[0.20.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.14.4...v0.15.0
[0.14.4]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.14.3...v0.14.4
[0.14.3]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.14.2...v0.14.3
[0.14.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.14.0...v0.14.2
[0.14.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.12.1...v0.13.0
[0.12.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.7.0...v0.7.1
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
