# Upgrading Recording Studio MCP

## 0.30.2

No MCP protocol migration. `ActiveRecord::RecordInvalid` and
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
