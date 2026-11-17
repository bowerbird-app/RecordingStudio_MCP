# Upgrading Recording Studio MCP

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
