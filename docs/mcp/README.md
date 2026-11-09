# MCP reference docs

Sourcey site for this gem's **built-in** MCP tools. Not a runtime dependency. Sourcey is AGPL-3.0. mcp-parser is MIT. Both live only in this folder's `package.json` `devDependencies`. They must not enter the gemspec or a host Gemfile.

JSON HTTP APIs stay on Scalar.

## Refresh

The dummy app must be seedable. `bin/docs-mcp` from the repo root:

1. Boots the dummy MCP endpoint if it is not up.
2. Mints an edit-role Seed MCP App token (not committed).
3. Snapshots `http://127.0.0.1:3000/recording_studio_mcp`.
4. Drops host-only tools, instance `recording://` rows, and local URLs.
5. Validates with `npx mcp-parser validate`.
6. Builds static HTML to `dist/` (`npx sourcey build`).

`dist/` and `node_modules/` are gitignored. Commit `server.snapshot.json` after a tool-surface change.

Override the URL with `MCP_URL`.
