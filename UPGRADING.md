# Upgrading Recording Studio MCP

## 0.29.0

No MCP protocol migration. `tags` and `outputSchema` on tools are optional.

Mounted docs (`recording_studio_mcp_docs_for`) now group tools in the Redoc sidebar
and show each type's operations, writable fields, and capability actions on the
type schema. The page overview is human Markdown. Initialize `instructions` sent
to MCP clients are unchanged in meaning.

If you displayed `info.description` as the agent instruction dump, read
`x-mcp.instructions` instead.

Endpoint tools include `outputSchema` only when that endpoint's `openapi` hash
already has a success JSON response schema. `RecordingStudioApi.register_endpoint`
still has no dedicated response-schema argument. Do not add one in this gem.
