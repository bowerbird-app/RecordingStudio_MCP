# Dummy app

This Rails host proves `recording_studio_mcp` as a remote MCP HTTP endpoint.

## What it covers

- Devise sign-in (`admin@admin.com` / `Password`)
- Oauth + API + MCP stacked like a real host
- Seed MCP App as a public PKCE OauthClient
- Studio Workspace starts Connected
- Site name `Studio` from Site settings
- MCP URL at `/recording_studio_mcp`
- Ops MCP at `/recording_studio_mcp/apis/operations` (operations named API; `api_key` is that label, not a secret)
- Oauth `v0.6.2` (ops clients can Connect on Admin)
- Dummy-only `/docs/mcp` (mentions `describe`)
- Dummy-only `demo_progress` MCP tool (`RecordingStudioApi.register_endpoint`, progress under Puma)
- Dummy registers `recording updated` and `page commented`, and enables MCP Events
- `/pages` lists pages the signed-in person can see, each with an inline save form; **Ping watchers** fires the custom event; saving also fires `recording.updated` webhooks
- `/mcp_event_receiver` is a local signed webhook inbox
- Home still has an **Edit recording** button that saves a page so a subscribed client is notified
- Signed-in FlatPack sidebar: Home, Pages, Webhook inbox, Try MCP, Oauth registered apps, Sign out
- Oauth registered apps at `/admin/screens/oauth_clients` (Oauth gem admin UI; lists DCR clients too)
- Dummy Oauth sets `config.allow_self_registered_apps = true` so MCP Inspector can RFC 7591 register after RFC 8414 discovery
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
- `/pages` pages the signed-in person can edit
- `/mcp_event_receiver` local signed webhook inbox
- `/docs/mcp` Try MCP
- `/admin/screens/oauth_clients` Oauth registered apps (switch to Admin first)
- `/recording_studio_mcp` MCP endpoint (public)
- `/recording_studio_mcp/apis/operations` ops MCP endpoint
- `/recording_studio_oauth/oauth/authorize` Connect (public apps)
- `/recording_studio_oauth/apis/operations/oauth/authorize` Connect (operations apps)
- `/recording_studio_api/oauth/token` API token URL
- `/recording_studio_api/apis/operations/oauth/token` operations token URL
- `/.well-known/oauth-protected-resource` 404 by default (origin unsuffixed)
- `/.well-known/oauth-protected-resource/recording_studio_mcp` MCP metadata (public)
- `/.well-known/oauth-protected-resource/recording_studio_mcp/apis/operations` ops MCP metadata
- `/.well-known/oauth-protected-resource/recording_studio_api/api` API metadata
- `/recording_studio_oauth/.well-known/oauth-protected-resource` Oauth engine API metadata
- `/.well-known/oauth-authorization-server/recording_studio_oauth` RFC 8414 path-inserted Oauth metadata
- `POST /recording_studio_oauth/register` RFC 7591 self-registration (dummy has it on)
- `/docs/mcp` dummy-only MCP try-it page
- `POST /docs/mcp/test_token` dummy-only mint + MCP probe (signed in, local only)
- `POST /docs/mcp/sample_post` dummy-only HTTP sample POST with Bearer (signed in, local only)
- `/users/sign_in` Devise
