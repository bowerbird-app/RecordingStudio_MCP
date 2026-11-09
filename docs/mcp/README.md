# MCP reference docs (example dummy surface)

Sourcey site for a **committed dummy snapshot** of this gem's built-in MCP tools. Hosts that need live types should mount `recording_studio_mcp_docs_for`, not this folder. Not a runtime dependency. Sourcey is AGPL-3.0. mcp-parser is MIT. Both live only in this folder's `package.json` `devDependencies`. They must not enter the gemspec or a host Gemfile.

JSON HTTP APIs stay on Scalar.

## Refresh

The dummy app must be seedable. `bin/docs-mcp` from the repo root:

1. Runs `npm ci` in `docs/mcp`.
2. Boots the dummy MCP endpoint if it is not up.
3. Mints an edit-role Seed MCP App token (not committed).
4. Snapshots `http://127.0.0.1:3000/recording_studio_mcp`.
5. Drops host-only tools, instance `recording://` rows, and local URLs.
6. Validates with `npx mcp-parser validate`.
7. Builds static HTML to `dist/` (`npx sourcey build`).

`dist/` and `node_modules/` are gitignored. Commit `server.snapshot.json` after a tool-surface change.

Override the URL with `MCP_URL`.

## Publishing

Any of these can host the static `docs/mcp/dist` output. None is chosen:

- GitHub Pages (Actions upload of `docs/mcp/dist`, or `/docs` if you commit HTML)
- Cloudflare Pages
- Netlify / Vercel / S3+CloudFront / any static file host
- Serve `dist/` from the host Rails app (for example a non-engine static mount)
- Sourcey Cloud / another docs host
- Keep it unpublished and generate locally with `bin/docs-mcp`
