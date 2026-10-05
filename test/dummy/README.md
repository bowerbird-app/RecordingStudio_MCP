# Dummy app

This Rails host proves `recording_studio_mcp` as a remote MCP HTTP endpoint.

## What it covers

- Devise sign-in (`admin@admin.com` / `Password`)
- Oauth + API + MCP stacked like a real host
- Seed MCP App as a public PKCE OauthClient
- Studio Workspace starts Connected
- Site name `Studio` from Site settings
- MCP URL at `/recording_studio_mcp`
- Dummy-only `/docs/mcp` (mentions `describe`)
- Dummy-only `demo_progress` MCP tool (`RecordingStudioApi.register_endpoint`, progress under Puma)
- Signed-in FlatPack sidebar: Home, Try MCP, Oauth registered apps, Sign out
- Oauth registered apps at `/admin/screens/oauth_clients` (Oauth gem admin UI; lists DCR clients too)
- Signed-in “Try MCP” / “Sample POST” on `/docs/mcp` (local/dev/test only) mint a real `rsoauth_at_…` token, probe MCP, then POST `/recording_studio_mcp` so the grant resolves over HTTP

Token URL stays on the API engine. MCP authenticates `rsoauth_at_` tokens through Oauth's TokenAuthenticator. The same token works with MCP and the named API on purpose; both resolve the same AccessGrant.

Progress streams only for `tools/call` with a string/integer `params._meta.progressToken` and `Accept: text/event-stream`. Run the dummy with Puma (`bin/rails server` / `bin/dev`), not a buffering proxy, and probe with `curl -N`. See the gem README.

## Quick start

```bash
cd test/dummy
bundle install
bin/rails db:setup
bin/dev
```

Open port 3000. Sign in with `admin@admin.com` / `Password`.

## Routes

- `/` dummy home
- `/docs/mcp` Try MCP
- `/admin/screens/oauth_clients` Oauth registered apps (switch to Admin first)
- `/recording_studio_mcp` MCP endpoint
- `/recording_studio_oauth/oauth/authorize` Connect
- `/recording_studio_api/oauth/token` API token URL
- `/.well-known/oauth-protected-resource` 404 by default (origin unsuffixed)
- `/.well-known/oauth-protected-resource/recording_studio_mcp` MCP metadata
- `/.well-known/oauth-protected-resource/recording_studio_api/api` API metadata
- `/recording_studio_oauth/.well-known/oauth-protected-resource` Oauth engine API metadata
- `/docs/mcp` dummy-only MCP try-it page
- `POST /docs/mcp/test_token` dummy-only mint + MCP probe (signed in, local only)
- `POST /docs/mcp/sample_post` dummy-only HTTP sample POST with Bearer (signed in, local only)
- `/users/sign_in` Devise
