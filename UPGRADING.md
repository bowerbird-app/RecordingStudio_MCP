# Upgrading Recording Studio MCP

## 0.30.2

Previous version is `0.30.0`. No MCP protocol migration. Docs-only.

Mounted MCP docs (`/mcp-docs`, Redoc) put each registered type and its
capability actions under that type's Recording Studio API OpenAPI tag. Types
with no tag stay under Types. Each tag still appears once. There is no default
`x-tagGroups`.

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
