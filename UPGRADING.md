# Upgrading Recording Studio MCP

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
