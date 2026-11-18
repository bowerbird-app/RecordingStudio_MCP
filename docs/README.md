# MCP docs

Hosts mount **live** docs with `recording_studio_mcp_docs_for`. That page builds an OpenAPI 3.1 document from the host catalog on each request and renders it with vendored Redoc. `{mount}/fullscreen` is the same viewer without the host layout. There is no committed tool snapshot. Each tool tag is a top-level sidebar section. `Overview` is first, then the remaining tags in alphabetical order, then `Other tools`. There is no Core group and no Tools group. Ping and the general tools sit under Overview. A gem may set `tag_suffix` on a capability action's OpenAPI, once or per type. The sidebar tag is the type group plus that suffix (`Video Trash` follows `Video`). `tag_suffix` is not copied onto the operation. An action summary and description use the per-type OpenAPI value when set, and the shared action copy otherwise. The Recording resource is not in the sidebar. Types list their capability actions. That page ends with a `Tool:` line for the action and for each general operation the type allows. A type with no capability action has no sidebar page. A type with no tags uses its public name. The Overview is the initialize instructions for that API, plus one line: a view-only connection gets the same text minus the Make changes part. The page has no grant. `x-mcp.instructions` stays the initialize text. Without JavaScript, the page shows that Overview, then lists tool names and titles in that tag order and links to the page's `openapi.json`. The sign-in gate is unchanged.

JSON HTTP APIs stay on Scalar.

## Guides

- [Introduction](introduction.md)
- [Connect with OAuth](oauth.md)
- [Cursor](cursor.md)
- [Claude Code](claude-code.md)

## Example dummy app spec

`bin/docs-mcp` writes `docs/example-app.openapi.json` from the dummy app's live public catalog. Open `docs/example-app.html` next to that file if you want a static Redoc page of the **example dummy app**. Do not serve that file as product docs.
