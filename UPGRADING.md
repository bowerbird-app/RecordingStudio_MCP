# Upgrading Recording Studio MCP

## 0.49.0

Previous version is `0.48.1`. No MCP migration.

A blank `parent_id` is no longer rejected before the API runs. The tool error names the type, for example `parent_id is required for PressKit`. `parent_id` text names that type's allowed parents. The sentence `A blank value then uses that workspace` stays only when this connection's workspace is an allowed parent.

A named or custom tool given an id of a different type in this grant and this API names that type and the tool to call, for example `This id is a KitSection. Use kit_section_show.` An id outside the grant stays `Resource was not found in this API scope`. Public and operations APIs stay separate.

Initialize reports `tools.listChanged: true`. A live session that has already called `tools/list` or `tools/call` receives `notifications/tools/list_changed` on the next `tools/list` or `tools/call` when that list differs. The notice goes out on that process's listen stream, including `subscriptions/listen` on protocol `2026-07-28`. A client that is not listening does not receive it. A deploy drops in-memory sessions, so the notice does not cross a restart. Reconnect after a deploy when the app ignores the notice.

## 0.48.1

Previous version is `0.48.0`. No MCP migration.

A docs tag is shown only when a tool on that server carries it. Intro text does not keep a tag. The fullscreen sidebar, the no-JS list, and `x-tagGroups` use that rule. An `x-tagGroups` group whose tags are all hidden is left out. Guide pages that are not tags stay.

## 0.48.0

Previous version is `0.47.1`. No MCP migration. Hosts must upgrade `recording_studio_api` to `>= 1.22.0`.

When an API create catalog entry says `parent` is `server`, MCP does not ask for `parent_id` and does not send one. That covers the generic `create` tool for that type, a named create tool, and a capability action that creates. A `parent_id` a caller still sends is ignored. Creates that do not opt in are unchanged. A blank `parent_id` still uses the workspace when the workspace is an allowed parent.

## 0.47.1

No action needed.

Docs pages leave out a tag that has no tools and no intro text, in the fullscreen sidebar, the no-JS list, and `x-tagGroups`. A tag with intro text and no tools stays.

An unknown capability action lists registered MCP tool names. A contract failure names the MCP tool. A typeless action tool's `type` enum stays the types that enable the action. Its description keeps the host text and adds `Enabled on` those types.

A database deadlock, lock wait timeout, or lock-timeout cancel returns `Another change to this item is in progress. Try again.` The log line is still the exception class only.

When an id in this grant points at a different type that is also on this API, the tool error names that type and says to use the item's `content_id`. A type outside this API stays `Resource was not found in this API scope`.

## 0.47.0

Previous version is `0.46.0`. No MCP migration.

Leave `parent_id` blank on create when this connection's workspace is an allowed parent. MCP fills that workspace id before the API runs. When the workspace is not an allowed parent, `parent_id` stays required.

Named create tools, and action tools whose action has `creates: true`, take an optional `idempotency_key`. The same key and the same input return the first result. `describe` lists those names in `repeat_safe`.

A typeless action tool such as `attach` lists only types that enable that action. If no type enables it, the tool is not in `tools/list`.

`tools/call` maps `ActiveRecord::RecordNotFound` to `Resource was not found in this API scope`. Any other unexpected error is a tool result with `isError` and the text `Internal error`. The server log records the exception class only.

Call `read_skill` with a skill name from `describe`. The text is the same skill `resources/read` would return. A name this connection cannot see is `Skill was not found`.

A missing parent on create still says `Parent resource was not found in this API scope`, then lists the allowed parent types. When the workspace is one of those types, the message includes `Workspace id`.

## 0.46.0

Previous version is `0.45.2`. No MCP migration. Tool names from `RecordingStudioMcp.tool_name` are unchanged.

`RecordingStudioMcp::ToolName.type_singular_snake(type)` and `RecordingStudioMcp::ToolName.type_public_token(type)` are public. They return the API public name, demodulized (`press_kit` and `PressKit` for `PressKit` or `FeaturedIn::PressKit`).

## 0.45.2

Previous version is `0.45.1`. No MCP migration.

Capability actions (and any other tool) whose JSON result is an array now wrap MCP `structuredContent` as `{ "records": [...] }`, the same as `list`. Text content is that object. Hash results are unchanged.

Read `structuredContent.records` when the action returns a list. Spec-compliant MCP clients reject a bare array.

A named capability-action tool registered without `type` now requires `type` in `inputSchema`, the same way it already requires `id`. Callers still pass the host type in args. `describe` lists that tool under every registered type that enables the action (for example Attachable `create_upload` on each attachable type). Typed named tools and generic tree tools are unchanged.

## 0.45.1

Previous version is `0.45.0`. No MCP migration for typed tools or generic tree tools.

A named capability-action tool registered without `type` now advertises the API action `inputSchema` (contract fields plus `id`). Callers still pass `type` in args for the host record. Leave `type` off `register_tool`. `type: ""` is not needed.

```ruby
RecordingStudioMcp.register_tool(
  name: "create_upload",
  action: :create_upload,
  title: "Create upload",
  description: "Create an upload on the host type passed in args.",
  input: {},
  output: "the upload"
)
```

An unknown action name on that shape now raises at boot, the same as a typed named action. Generic `list` / `show` / `create` / `update` / `delete` / `capability_action` are unchanged.

## 0.45.0

Previous version is `0.44.0`. This is a breaking change. No MCP migration.

### Changed (breaking)

Updates now reject immutable fields with `<field> cannot be changed on update`. Create still accepts those fields. Stop sending create-only fields on `update`.

Named `register_tool(operation:)` tools now advertise the same protocol fields as generic `list` / `show` / `update` / `delete`. `type` stays omitted when the registration already forces it. A missing `id` on show, update, or destroy returns the tool error `id is required` instead of a scope miss. Gem `input` / contract properties still win when they already define the same key.

## 0.44.0

Previous version is `0.43.5`. This is a breaking MCP tool-name change for named typed tools.

Gems pick readable tool names, as much as possible in `verb_type` form (`show_press_kit`, `feature_press_kit`, `add_quote_section`). When `verb_type` does not fit, use any readable snake_case name. `RecordingStudioMcp.tool_name` is an optional helper for the `verb_type` form. Only duplicates raise. Generic tree tools stay `list`, `show`, `create`, `update`, `delete`, and `capability_action`.

The helper's `verb_type` form uses the plural type for `list` (`list_press_kits`). If the action already ends with the type noun, it does not repeat it (`add_image` on an Images type stays `add_image`). If the action's trailing word(s) match the type's leading word(s), those words are not repeated (`add_quote` on `QuoteSection` is `add_quote_section`).

Rename callers from the old `Type--action` form to the new name. Include the new name on `register_server`.

| Old name | New name |
| --- | --- |
| `PressKit--show` | `show_press_kit` |
| `PressKit--create` | `create_press_kit` |
| `PressKit--list` | `list_press_kits` |
| `PressCenter--feature_kit` | `feature_press_kit` |
| `Workspace--ping` | `ping_workspace` |

Named `operation` tools still map the registered class name through `displayed_type_name` then `resolve_type!`. Generic `create` / `show` / `list` still reject a class name for `type`. Keep `type:` on `register_tool` as the API class name.

Re-registering a tool name still overrides title, description, and input copy only. A host override that changes type or target still raises at boot.

## 0.43.5

Previous version is `0.43.4`. No MCP migration.

`describe` still keeps `parent` when there are no parent rules; the value is `null`. The `describe` `outputSchema` now types `parent` as object or null. `capability_actions` is still omitted from the payload and from `describe`'s `outputSchema` when the named server does not include `capability_action`.

## 0.43.4

Previous version is `0.43.3`. No MCP migration.

Named `register_tool(operation:)` tools (`Type--create`, `Type--show`, and the rest) map the registered class name through `displayed_type_name` then `resolve_type!`, the same public-name catalog generic tools use. Generic `create` / `show` / `list` still reject a class name for `type`. Keep `type:` on `register_tool` as the API class name.

## 0.43.3

Previous version is `0.43.2`. No MCP migration.

`describe` and docs type fields always include `parent`. When Recording Studio has no parent rules for that type, the value is `null`. `capability_actions` is still omitted from the payload and from `describe`'s `outputSchema` when the named server does not include `capability_action`.

## 0.43.2

Previous version is `0.43.1`. No MCP migration.

Docs, initialize Overview, and `describe` follow the same `include_tools` list as `tools/list` for that named server. `describe` is always present. If `capability_action` is not included, `describe` omits `capability_actions` and type docs do not list those actions. Generic `create` / `list` / `show` / `update` are not named when they are not included. A `tools/call` for an excluded name is an unknown-tool error.

## 0.43.1

Previous version is `0.43.0`. No MCP migration.

MCP docs list exactly the live tools for that named API. The OpenAPI `x-mcp.tools` array is `Tools.definitions` for that API, the same set `tools/list` returns when there is no grant. Docs no longer add `{type}--{action}` copies of capability actions. A capability action without `register_tool` is not a sidebar tool. It stays on `capability_action` and in `describe`.

Named `Type--*` tools use that type's sidebar tag. Generic tree tools stay under Overview.

Each type's group intro is that type's `describe` payload: paragraph, tools that apply to the type (generic `create` / `list` / `show` when `describe` lists them, plus named `Type--*` tools), capability action names (plus the creates/idempotency_key line when that action creates), parent rules, and relationships. A type without `delete` in `describe` does not show `delete` on the docs page.

## 0.43.0

Previous version is `0.42.1`. No MCP migration.

`describe` returns `parent` (`root`, `allowed_parent_types`), `writable_fields` as hashes (`name`, `required`, `type`, `allowed_values`, `description`, `immutable_on_update`), and `capability_actions`. Copy still comes from `register_type`. Field types, enums, and actions come from the API registration and Recording Studio declarations. Do not add those keys to `register_type`.

`register_tool` stays `name`, `title`, `description`, optional `type`, exactly one of `operation` / `action` / `endpoint`, `input` (copy overlay only), and `output`. `register_type` stays `type` and `description`. That is the shape other gems copy. See the README.

Create `parent_id` is required in the tool schema when `RecordingStudio.root_allowed?` is false, which is the same rule Recording Studio API uses on create. MCP does not add a second parent check. A wrong parent still surfaces the Recording Studio API / core message.

Capability and endpoint contract errors name the field and the rule (`checksum is required. MD5 checksum of the file bytes, Base64-encoded…`, `kind must be one of: image, file`). A plan `RecordingStudio::Denial` or `RecordingStudio::AuthorizationError` from an action is an MCP tool error, not `-32603`.

## 0.42.1

Previous version is `0.42.0`. No MCP migration.

Named typed tools pass the catalog API when MCP UI looks up a widget. Hosts that load MCP UI no longer see `initialize` fail with `ConfigurationError` because `ui_for` received a nil API.

## 0.42.0

Previous version is `0.41.1`. No MCP migration.

Development and dummy Gemfiles move to the flat_pack 0.2 sweep tags. `recording_studio_api` stays on tag `v1.21.3` (`~> 1.21`). Gemspec floors are unchanged.

flat_pack 0.2.0 is supported; hosts moving to 0.2 must remove the manual `flat_pack/heroicons` importmap pin and any `flat-pack--icon` controller registration.

Hosts MUST run the Recording Studio 7.4, 7.5 and 7.7 migrations if they have not.

## 0.41.1

Previous version is `0.41.0`. No MCP migration.

`describe` and other tools tell callers to call `describe`. There is no docs tool.

Generic tools accept only the public type name. `PressKit` selects `RecordingStudioPresskits::PressKit`. The class name is still rejected on `list`, `create`, `update`, `delete`, `capability_action`, and `describe`. Named `{type}--{action}` tools pass the registered class name through the same public-name catalog without that public resolver.

Named `{type}--{action}` tools include `id` when the action targets an existing recording. A contract field named `type` stays on the schema. Send those fields at the root. `params` still works. A root field overrides `params` when both set the same key.

`create` schemas mark `parent_id` required when the type is not a root. A missing value is refused by Recording Studio API on the builtin create path.

## 0.41.0

Previous version is `0.40.2`. No MCP migration.

`include_tool` `title:` and `description:` now apply to metric tools. Typed tools already used that BuiltTool host copy. Recordable metric tools list `MetricEntry#title`, and fall back to the capitalized identifier only when that title is blank.

Boot raises `RecordingStudioApi::ConfigurationError` when a server includes a catalog metric whose resource is not in `catalog_metric_resources`. Runtime `tools/list` already left those tools out. Add the resource to the allowlist, or stop including the tool. A nil allowlist still includes every catalog metric.

## 0.40.2

Previous version is `0.40.1`. No MCP migration.

A named `register_tool` for a recordable type and capability action is the only docs entry for that type/action. The `{type}--{action}` `x-mcp-docs-only` copy is omitted when that named tool is on the server. Type/actions with no named tool still get the docs-only page.

## 0.40.0

Previous version is `0.39.2`. This is a breaking MCP surface change.

Require `recording_studio_api` `>= 1.21.3`, `< 2.0`. MCP looks up handlers with `RecordingStudioApi.lookup`. Do not keep a second API registry in the host. Create and update input schemas come from `RecordingStudioApi::Services::DocumentationCatalog.attributes_schema_for`, plus lookup `required` and `allow_blank` (`minLength: 1`). Host copy may change descriptions and examples only. Update fields stay optional.

Tools are opt-in. Register each tool, type, and skill, then include them on a named-API server:

```ruby
RecordingStudioMcp.register_tool(name: "ping", endpoint: :ping, title: "Ping", description: "...", input: {}, output: "ok")
RecordingStudioMcp.register_type(type: "Page", description: "A page under a folder or workspace.")
RecordingStudioMcp.register_skill(name: "page-desk", type: "Page", title: "Page desk", description: "...", body: "...", tools: %w[list show describe])
RecordingStudioMcp.register_server(:public, api: :public) do
  include_tools :list, :show, :create, :update, :ping
  include_skills "page-desk"
end
```

`list`, `show`, `create`, `update`, `delete`, and `capability_action` still exist, but only when included. `describe` is always on. It no longer lists operations, writable fields, or capability action contracts. Call docs or the API registration for those. Type paragraphs and relationships come from `register_type` and the API.

Sensitive API items need `allow_sensitive: true` on the server or on `include_tool`. Host overrides of a tool name may change title, description, and input copy only. Type, target, required, and non-empty rules stay on the API contract.

Boot raises when a registration names something the API does not have. Run `rake recording_studio_mcp:audit` in host CI.

Metric and endpoint tools are included by their MCP names (hyphenated metric names, endpoint names). They are not auto-listed from the API catalog.

Do not mention Access in MCP descriptions. Copy is for humans and agents: what the recording is, its purpose, and write prerequisites.

## 0.39.2

Previous version is `0.39.1`. No MCP migration.

A capability action page shows one `Tool:` line, for that action. The idempotency sentence is included only when the action or its resource handler is flagged `creates: true`. Other actions leave it off.

Each type's allowed `list`, `show`, `create`, `update`, and `delete` lines are on that type's group intro, once. Only operations that type allows on the named API are listed. A type with those operations and no capability action still has the group. A tag with no tools and no core lines is left out of the sidebar.

Hosts that read those core lines from an action page should read the group intro instead.

## 0.39.1

Previous version is `0.39.0`. No MCP migration.

Require `recording_studio_api` `>= 1.19.0`, `< 2.0`. The 0.39.0 replay entry is unchanged. Create and a flagged `capability_action` now pass `RecordingStudioApi::IdempotencyStore.fingerprint` for the method, path, and effective input. The same key with a different input returns a tool error, code `idempotency_key_reused`, message `Idempotency key already used with different parameters`. `idempotency_key` and a stripped `authorized_by` are left out of the fingerprint. A stored result with no fingerprint still replays. The fingerprint is not written to usage logs. A custom create with a different body is that mismatch error. Builtin create still uses the API resource operation.

Initialize instructions say to send the same `idempotency_key` when retrying a create, or a write action flagged `creates: true`, with the same input. A different input for that key is an error. Hosts that quote the old "create only" sentence will see the new wording.

The docs sidebar has no Core group and no Tools group. Ping and the general tools sit under Overview. Overview is first. Other tools stays last. A capability action page ends with a `Tool:` line for that action and for each general operation the type allows. There is no separate page per operation. A type with no capability action has no sidebar page. A page only lists operations that type allows on that named API.

The docs Overview is the full initialize text, plus one line: a view-only connection gets the same text minus the Make changes part. `x-mcp.instructions` and a view-only connection stay on the initialize text. A view-only connection does not get the Make changes section.

## 0.39.0

Previous version is `0.38.0`. No MCP migration.

Require `recording_studio_api` `>= 1.18.0`, `< 2.0` and `recording_studio_admin` `>= 2.19.0`, `< 3.0`. The API gem requires Recording Studio `>= 7.7.0`, `< 8.0` and Accessible `>= 0.50.0`, `< 2.0`. It refuses to boot with Admin older than `2.19.0`. Add `config/recording_studio_api.yml` if the host does not have one. A missing file raises while the API engine loads. An empty file with `development`, `test`, and `production` keys is enough when you do not set API options there.

`capability_action` still accepts `idempotency_key` at the top level, the `Idempotency-Key` header, or a key inside `params` when the other two are absent. Replay runs only when the action or its resource handler is flagged `creates: true`. The same key and the same input return the first result and do not create another record. A new key runs the action again. The same key with different input is refused with `Idempotency-Key was already used with different input`. A blank key runs the action. An action that is not flagged ignores the key, including a read action.

A repeated key on a different action or record is a separate replay. It runs. `0.37.4` treated that repeat as an error.

A custom `create` handler uses the same `Idempotency.replay` entry and still returns the first response when the body differs. Builtin create is unchanged.

## 0.38.0

Previous version is `0.37.4`. No MCP migration.

Initialize `instructions` are short lines under headings. The docs Overview for an API is that same text. The docs page has no access grant, so `Instructions.text` uses the page's API surface. A callable `instructions_suffix` receives `access_grant: nil` on that page. Return nil from the callable to leave the suffix off. A string suffix is shown under Guides.

The line that begins `If you only see named route tools` is present only when the surface has endpoint tools and no tree tools. On that surface, one tool is one named route, and path parameters are arguments.

`tools.listChanged` is still false. The instructions say the tool list is not refreshed on its own.

The docs sidebar has no Core group. Remaining tags are alphabetical. `Other tools` is last. The general tools are explained in the Overview and are left out of the sidebar. Per-type pages still show how to call a general tool with that type or action. They are reference pages, not extra tools. Each operation the type allows (`list`, `show`, `create`, `update`, `delete`) has its own page and ends with a `Tool:` line. `list` includes `parent_id` only when that surface advertises it. A host `ping` endpoint with no tag is under `Other tools`. The no-JS list follows the same tag order and includes the Overview.

Hosts that parsed the old instruction sentences, or that linked people to the Core group, should check those clients and pages.

## 0.37.4

Previous version is `0.37.3`. No MCP migration.

`capability_action` accepts an optional top-level `idempotency_key`. The `Idempotency-Key` header counts too. A key inside `params` is removed before the action input contract. That key still counts when the top-level argument and the header are absent. The same key on the same action, type, and record returns the first result and does not run the action again. The same key on a different action, type, or record is an error. A read action ignores the key. The API idempotency store keeps the result for that named API and client, so a public token and an operations token do not share it. Create replay is unchanged.

`describe` includes `nesting`. Nested items such as attachments and locations are managed through the parent type's actions (for example `add_image`), not as their own types. They stay out of the type enum.

## 0.37.3

Previous version is `0.37.2`. No MCP migration.

A second `create` with the same `idempotency_key`, or the same `Idempotency-Key` header, returns the first record. That includes a type whose create is a custom resource handler. The API idempotency store keeps the response for that client. The builtin create path is unchanged.

Tool results still use the registered public name for `type` and `recordable_type`. An unregistered value that contains `::` now shows its last segment. `RecordingStudioAttachable::Attachment` shows `Attachment`. `RecordingStudio::Location::Location` shows `Location`. A string with no `::` stays as the API sent it. `list`, `show`, `create`, and `describe` still resolve a registered public name. A name that is not registered is an unknown type error.

## 0.37.2

Previous version is `0.37.1`. No MCP migration.

Tool results use the registered public type name for `type` and `recordable_type`. That includes list rows, nested records, and capability action results such as a trash bin. An unregistered type string stays as the API sent it. Callers still send the public name. A full class name is still rejected.

An untitled resource name is the public name, a space, and the recording id. A record with a real title keeps that title.

`describe` returns nested field schema on each writable field. Create lists that schema on required fields and on optional fields that declare it. Update lists it on writable fields that declare it. Fields that were only a type, allowed values, and a description stay the same.

The docs page still renders Redoc. Without JavaScript it lists tool names and titles in the sidebar tag order and links to `{mount}/openapi.json`. `documentation_enabled` and `documentation_access` are unchanged.

## 0.37.1

Previous version is `0.37.0`. No MCP migration.

A saved recording checks live SSE listeners once per access grant. Listeners share one Accessible scope check for that dispatch when each grant has already built its scope and the whole prime-time snapshot matches, including the parent recording, role, owner, and whether that snapshot is revoked or trashed. A grant that has not built its scope is checked on its own. A trashed or revoked snapshot is refused and is not reused. The next save checks again. The check is the same scope a resource read uses.

Webhook subscriptions are enqueued on the save with the subscription id, the recording id, and the event id. The request does not build the JSON body. `DeliverEventWebhookJob` loads the subscription and the grant again, runs that scope, builds the body, and only then posts. Delivery is at-least-once. A retried job posts again with the same webhook-id, and the access check runs again on that attempt. A missing subscription, a revoked grant, or a trashed grant is not delivered.

Drain the `recording_studio_mcp_events` queue before upgrading. Jobs queued by `0.37.0` pass a `body` and are not performed.

## 0.37.0

Previous version is `0.36.5`. No MCP migration.

`resources/list` pages the grant's recordings by `id`, ascending. The default page size is 100. Set `config.resources_page_size` to a positive integer to change it. When more recordings remain, the result includes `nextCursor`. The last page omits it. Clients must follow `nextCursor` until it is absent. Sending the cursor back as `cursor` reads the next page.

The cursor is opaque. A malformed cursor is JSON-RPC `-32602`. The error message is `Invalid params` and does not include the cursor. Each page loads that grant's accessible recordings again and keeps rows after the cursor id. A cursor cannot reveal a recording the grant cannot access. Recordables are loaded for the recordings on that page.

Skill resources and MCP UI widgets are on the first page. Later pages are recordings only. `resources/read` and `resources/templates/list` are unchanged. `resources/templates/list` still rejects a cursor.

On Accessible 0.47, every root page re-runs the stored-root mismatch probe, about 86 ms, and every subtree page runs the full descendant walk. Accessible 0.49 removes both. That update comes with the ecosystem dependency sweep. The Accessible pin stays.

## 0.36.5

Previous version is `0.36.4`. No MCP migration.

A capability action that returns a recording is serialized with that call's access grant, scoped recordings, and arguments. Fields that depend on the grant are in the write result. `show` already used this grant.

The `create` tool still requires `type` at the top level. It also lists each creatable type's required fields in an `allOf` branch. The `if` matches `type`. The `then` lists that type's required fields. The field list is the same one `describe` returns. Optional writable fields stay allowed. Tool name stays `create`.

`describe` and the docs page use a per-type action summary and description when `openapi_for` sets them. Otherwise they use the shared action copy. Tool names and `tools/list` are unchanged.

## 0.36.4

Previous version is `0.36.3`. No MCP migration.

The public docs sidebar lists Core first. Every other tag follows in alphabetical order. `Other tools` is last. `Press Kit` stays before tags such as `Press Kit List Section`.

The Recording resource is not in that sidebar. `resources/list` and `resources/read` still work.

Untagged tools take their recordable type's group. A type with no OpenAPI tags uses its public name. Workspace access actions (`grant_access`, `list_access`, `revoke_access`, `update_access`) sit under Workspace when that type is registered. A host `ping` endpoint sits under Core. A tool with no owner sits under `Other tools`. `Endpoints` and `Tools` are not fallback groups.

A capability action title uses the per-type OpenAPI title (`openapi_for`), then the action's own title, then `<singular type> - <humanized action>`.

A gem may set `tag_suffix` on the action OpenAPI. Set it once on the shared action, or per type in the `openapi_for` overlay. The sidebar tag is that type's group, a space, and the suffix (`Video` and `Trash` become `Video Trash`). Alphabetical order keeps `Video` before `Video Trash`. `tag_suffix` is not copied onto the operation. Tool names and `tools/list` are unchanged.

## 0.36.3

Previous version is `0.36.2`. No MCP migration.

Capability action titles in MCP docs and `describe` use the gem OpenAPI
title as written. `Add podcast` stays `Add podcast`. `Upload` stays
`Upload`.

Gems that relied on MCP prefixing the type onto a short title now get
that title verbatim. Include the type in the OpenAPI title, or leave
the title blank for the fallback `<singular type> - <humanized action>`.

A title that already contains ` - ` is unchanged. Tool names,
`tools/list`, tags, and grouping are unchanged.

## 0.36.2

Previous version is `0.36.1`. No MCP migration.

MCP now requires `recording_studio_api` `>= 1.6.0, < 2.0`. Development
and dummy Gemfiles pin API `v1.6.0`, Recording Studio `v7.6.0`, and
Accessible `v0.47.0`. API 1.6 needs Recording Studio `>= 7.6.0, < 8.0`
and Accessible `>= 0.46.0, < 2.0`. Run API's api client owner migration.
It adds `owner_type` and `owner_id`.

MCP reads `registration.public_name` and accepts only that string.
Set `public_name:` on `register_recordable_type_api`. A blank value is
the class name without its namespace. `RecordingStudioPresskits::PressKit`
still shows as `PressKit`.

A full class name is still rejected. Send the public name.

API raises `ConfigurationError` at boot when two types on one named API
share a public name. MCP does not rewrite those types to full class
names, and it does not log a warning.

## 0.36.1

Previous version is `0.36.0`. No MCP migration.

`describe` now includes `sortable_fields`. `list` `sort` accepts one of those fields. `created_at` is always allowed and is the default. `order` is `asc` or `desc`.

A path parameter with no OpenAPI description uses the endpoint's registered resource or its name, for example `The conversation id.` A lookup error is logged with the endpoint and parameter. The docs page still renders.

Capability action docs name the singular type with no article, such as `Runs on User records.` The public name is in parentheses only when it differs from that label, such as `Runs on Image records (Images).`

## 0.36.0

Previous version is `0.35.0`. No MCP migration. The API requirement stays
`>= 1.2.0, < 2.0`.

MCP shows recordable types by a short public name. `tools/list` type
enums, `describe`, docs tool names, docs tags, errors that list
allowed types, and resource reads use that name.
`RecordingStudioPresskits::PressKit` shows as `PressKit`. A docs action
is `PressKit--set_embargo`. Call `capability_action` with
`type: PressKit` and `action: set_embargo`. A resource read returns
`type: PressKit`.

A full class name is rejected. `type: RecordingStudioPresskits::PressKit`
returns the unknown-type error, which lists the allowed public names.
Callers must send `type: PressKit`. A resource name resolves only when
it is that same public name. `press_kits` does not select `PressKit`.
Public and operations APIs each keep their own map.

API is adding an optional `public_name:` argument to
`register_recordable_type_api`. That release is not out yet, so MCP
does not bump the API pin. When a registration responds to
`public_name` and the value is present, that value is the only accepted
name. Otherwise MCP uses the demodulized class name. The demodulized
name is rejected once `public_name` is present.

If two registered types on the same named API share a public name, MCP
does not pick one. Those types show and accept their full class names.
MCP logs a warning that the gem should set `public_name`. The shared
short name still returns the existing ambiguous-type error.

## 0.35.0

Previous version is `0.34.1`.

Runtime API is `>= 1.2.0, < 2.0`. Development and dummy Gemfiles pin
API `v1.2.0`. Other addon pins are unchanged.

Custom `show`, `update`, and `delete` handlers, custom capability
actions, and registered endpoints that capture `:id` or `:recording_id`
are scoped by `RecordingStudioApi::HandlerGuard` before the handler
runs. A blank id, a foreign root, the wrong recordable type, a trashed
record, and a role that is too low all return one tool error:
`Resource was not found in this API scope`. The handler does not run.
MCP does not forward the guard's message.

`owns_scoping` on a read, and an endpoint with `scope_id: false`, still
call the handler with `recording` nil. Flat MCP calls leave
`parent_recording` nil. There are no nested MCP tools.

A capability action input contract runs only after the guard allows the
call. Invalid params from a role that is too low still return the same
not-found sentence. The contract does not run.

Custom create is not a member lookup. The handler receives `recording`
and `parent_recording` as nil. `parent_id` is the client argument. The
handler scopes that parent. A handler with `include_trashed` still
receives a trashed recording when the role is allowed.

Built-in list, show, update, delete, and built-in capability actions
still use the accessible-recordings lookup.

## 0.34.1

Previous version is `0.34.0`. No MCP migration. Auth, token, and access
behavior are unchanged.

Runtime API is `>= 0.24.0, < 2.0`. Oauth stays `>= 0.22.0, < 1.0`.
Recording Studio stays `>= 7.0, < 8.0`.

Development and dummy Gemfiles pin Recording Studio `v7.1.0`, API
`v1.1.0`, Oauth `v0.24.0`, and Attachable `v0.31.0`.

Oauth `0.24` requires API `>= 1.0` and Recording Studio `>= 7.1`.
Attachable `0.31` requires API `>= 1.1, < 2.0`. A host that stays on
API `0.24` can keep Oauth `0.22` and Attachable `0.28`.

On API `0.26` and later, `register_endpoint` raises when the path
captures `:id` or `:recording_id` unless the endpoint passes
`recordable_type:` or `scope_id: false`.

## 0.34.0

Previous version is `0.33.3`. No MCP migration.

Runtime Recording Studio is `>= 7.0, < 8.0`. Oauth is `>= 0.22.0, < 1.0`.
API is `>= 0.24.0, < 1.0`. Logs are `>= 0.8.0, < 1.0`. Metrics are
`>= 0.9.0, < 1.0`. Admin is `>= 2.16.0, < 3.0`.

Development and dummy Gemfiles pin Recording Studio `v7.0.0`.

`RecordingStudio.root_recording_for` only finds a root. Seeds and other
setup that used to create a root by looking it up call
`create_root_recording!(recordable, actor:)`. The dummy `authorize_write`
allows a write when an actor is present.

Copy Recording Studio's events `root_recording_id` migration and run it.
Events store the recording's root.

Trashable `kept_sql` is gone. Filter with `Recording.kept`. Admin 2.16
dropped `site_admin_recording_resolver`. Point `access_recording_resolver`
at `RecordingStudioAccessible.admin_root`. Set
`admin_root_resolver` to the kept admin root. Site screens allow
`:site` only when that root is the access recording and the actor
is an admin on it.

## 0.33.3

Previous version is `0.33.2`. No MCP migration.

Runtime Recording Studio is `>= 6.0, < 8.0`. The lower bound is unchanged.
Development and dummy Gemfiles stay on tag `v6.7.0`.

## 0.33.2

Previous version is `0.33.1`. No MCP migration.

Runtime Recording Studio is `~> 6.0`. Runtime Admin is `>= 2.0, < 3.0`.
Runtime API is `>= 0.17.0, < 1.0`. Logs, metrics, and Oauth stay on their
`0.x` lines. Development and dummy Gemfiles still pin API tag `v0.22.1`.

## 0.33.1

Previous version is `0.33.0`. No MCP migration.

Runtime API is `>= 0.17, < 0.23`. Development and dummy Gemfiles pin API
tag `v0.22.1`. Released Oauth tags still cap API below `0.22`, so those
Gemfiles temporarily use Oauth branch `cursor/allow-api-0-22-7efb` until
a tag allows `< 0.23`. A host cannot install API `0.22.x` with Oauth
`v0.21.5`.

API 0.22 copies a matching `openapi.parameters` path entry's `description`
onto `openapi_path_parameters`. MCP tool arguments use that description.
A path parameter with no description still uses `Path parameter <name>.`

## 0.33.0

Previous version is `0.32.0`. No MCP protocol migration. Docs-only.

Capability action titles in MCP docs and `describe` are type first. A gem
OpenAPI title that already contains ` - ` stays. Other titles become
`<singular type> - <gem title or humanized action name>`. Duplicate-title
insertion is gone. Action pages show the gem OpenAPI description under
the summary when set. Protocol tools, routes, and action behaviour are
unchanged.

## 0.32.0

Previous version is `0.31.2`. No MCP protocol migration.

`describe` now includes capability action `title` and `summary` from the
RS_API OpenAPI registration, plus `description` when that field is set.
Blank keys stay off the payload. The type's registered OpenAPI description
is included when present.

MCP docs no longer emit per-type schema components. Action tool pages and
sidebar tags carry the type description instead. Protocol tools, API, and
`describe` contracts besides those extra keys are unchanged.

## 0.31.2

Previous version is `0.31.1`. No MCP protocol migration. Docs-only.

Capability action docs tools now use a JSON Schema `inputSchema` built from
the RS_API params definition (`EndpointSchema.build`), with a filled
example. The raw params dump is gone. Duplicate titles in one sidebar group
include the type label. Untagged namespaced types inherit that gem's type
group for action tools only. Action pages no longer list the type's writable
fields or allowed operations.

## 0.31.1

Previous version is `0.31.0`. No MCP protocol migration.

`RecordingStudio::ActorRequired` and `RecordingStudio::InvalidParent` now return MCP `isError` tool results instead of JSON-RPC `-32603`. The tool text is `error.message`. Tool errors that already have a `details` payload (API `InvalidActionInputError`) expose it as `structuredContent.details`. Unexpected `StandardError`s still return `-32603`.

## 0.31.0

Previous version is `0.30.3`. No MCP protocol migration. Docs-only.

Mounted MCP docs list each enabled capability action as a tool in the Redoc
sidebar, under the type's existing tag. Those entries set `x-mcp-docs-only`
and use the action input contract as `inputSchema` when present. Types stay in
the OpenAPI schemas and in MCP. Child and section types (registered under
another non-root recordable) omit a SCHEMA sidebar entry. The hide check is
`any?` over allowed parents, so a type allowed under both a root and a nested
parent also loses that sidebar entry. Top-level types keep theirs. Type class,
operations, and writable fields are on the action tool pages. `tools/list`
still advertises only `capability_action`.

## 0.30.3

Previous version is `0.30.2`. No MCP protocol migration. Docs-only.

Type schema titles use the core recordable label. The class name stays in
`Type: \`ClassName\`` and as the schema component key. Capability actions are
short `Tool: capability_action` entries, with one runtime note under the list.

Type entries use the same OpenAPI `tags` as that gem's endpoint tools. There is
no Types fallback group. Scalar `tag.group` is not a sidebar name.

## 0.30.2

Previous version is `0.30.1`. No MCP protocol migration. `ActiveRecord::RecordInvalid` and
`RecordingStudio::AuthorizationError` now return MCP `isError` tool results.
HTTP Recording Studio API still returns 500 for `RecordingStudio::AuthorizationError`.
MCP maps that write-gate denial so it is not a JSON-RPC internal. Builtin create
converts `RecordingStudio::InvalidParent` to `InvalidActionInputError` in
Recording Studio API, which MCP already maps. Other `StandardError`s stay
JSON-RPC `-32603`.

`describe` unions explicit `capability_actions` with
`RecordingStudioApi.capability_actions_for`, so auto-enabled Accessible access
actions appear in the list. Endpoint `input_contract` failures include the
contract error text (the bad field).

Pin runtime API `>= 0.17, < 0.22`. Development and dummy Gemfiles use API
`v0.21.0` and Oauth `v0.21.5` (Oauth `v0.21.0` still caps API below `0.18`).
API `0.21.0` needs Moveable `v4.1.0` and Icons `v0.2.0` on those Gemfiles.
API `write_actor` is `AccessGrant#actor`; delegated OAuth writes may use the
Accessible grant actor and store the OAuth client as impersonator.

## 0.30.1

Previous version is `0.30.0`. No MCP protocol migration. Docs-only.

Mounted MCP docs (`/mcp-docs`, Redoc) put each registered type and its
capability actions under their API tag group. Types with no tag stay under
Types. Each tag still appears once. There is no default `x-tagGroups`.

Each capability action entry explains that it is a capability action: call it
through the `capability_action` tool with the type and action name. `describe`
lists it at runtime.

## 0.30.0

No MCP protocol migration. The mounted docs sidebar no longer groups tags under
Core, Endpoints, Metrics, and Types. Each tool tag is a top-level Redoc section
and appears once. `x-mcp.tools[]` `tags` are unchanged.

If you consumed default `x-tagGroups`, stop. Pass `tag_groups` on the
documentation page only when you want a custom grouping.

## 0.29.0

No MCP protocol migration. Optional MCP `outputSchema` may appear on `tools/list`.
Docs `tags` are on `x-mcp.tools[]` only. They are not part of the protocol tool
payload.

Mounted docs (`recording_studio_mcp_docs_for`) now group tools in the Redoc sidebar
and show each type's operations, writable fields, and capability actions on the
type schema. The page overview is human Markdown. Initialize `instructions` sent
to MCP clients are unchanged in meaning.

If you displayed `info.description` as the agent instruction dump, read
`x-mcp.instructions` instead.

Endpoint tools include `outputSchema` only when that endpoint's `openapi` hash
already has a 2xx `application/json` object schema (`200`, then other 2xx, then
`2XX`). Error, default, array-root, and `$ref`-only schemas are skipped.
`RecordingStudioApi.register_endpoint` still has no dedicated response-schema
argument. Do not add one in this gem.
