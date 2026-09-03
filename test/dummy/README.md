# Dummy app

This Rails host proves `recording_studio_mcp` as a remote MCP HTTP endpoint.

## What it covers

- Devise sign-in (`admin@admin.com` / `Password`)
- Oauth + API + MCP stacked like a real host
- Seed MCP App as a public PKCE OauthClient
- Studio Workspace starts Connected
- Site name `Studio` through Site settings
- MCP URL at `/recording_studio_mcp`
- Dummy-only `/docs/mcp`

Token URL stays on the API engine. MCP authenticates `rsoauth_at_` tokens through Oauth's TokenAuthenticator.

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
- `/recording_studio_mcp` MCP endpoint
- `/recording_studio_oauth/oauth/authorize` Connect
- `/recording_studio_api/oauth/token` API token URL
- `/.well-known/oauth-protected-resource` Oauth metadata
- `/docs/mcp` dummy-only MCP URL
- `/users/sign_in` Devise
