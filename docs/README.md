# MCP docs

Hosts mount **live** docs with `recording_studio_mcp_docs_for`. That page builds an OpenAPI 3.1 document from the host catalog on each request and renders it with vendored Redoc. `{mount}/fullscreen` is the same viewer without the host layout. There is no committed tool snapshot. Each tool tag is a top-level sidebar section. Types list their actions. The overview is Markdown for people, not the agent instruction dump.

JSON HTTP APIs stay on Scalar.

## Guides

- [Introduction](introduction.md)
- [Connect with OAuth](oauth.md)
- [Cursor](cursor.md)
- [Claude Code](claude-code.md)

## Example dummy app spec

`bin/docs-mcp` writes `docs/example-app.openapi.json` from the dummy app's live public catalog. Open `docs/example-app.html` next to that file if you want a static Redoc page of the **example dummy app**. Do not serve that file as product docs.
