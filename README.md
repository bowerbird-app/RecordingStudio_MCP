# Recording Studio MCP

Mount this engine on a Recording Studio host. It exposes a remote MCP HTTP endpoint. Access is user-delegated OAuth. Domain actions come from Recording Studio API. This gem is a protocol adapter. It is not a second API and not an authorization server.

People Connect an app. The app gets its own Accessible grant. MCP then uses that same grant. The app does not act as the person.

## What you get

A Streamable HTTP MCP endpoint on the host. Unauthenticated calls return `401` with `WWW-Authenticate` pointing at Oauth's RFC 9728 protected-resource metadata. Clients authorize with authorization-code + PKCE S256 against Oauth (`/oauth/authorize`). Token exchange stays on API `POST /recording_studio_api/oauth/token`. MCP authenticates the Bearer with `RecordingStudioApi.access_grant_from_authorization_header`.

Authorization is Recording Studio Accessible through that AccessGrant. Same grant as API. No Pundit. No OAuth scopes.

Tools are a small parameterized set over the named API the OauthClient is bound to:

- `list`
- `show`
- `create`
- `update`
- `capability_action`

Not one MCP tool per OpenAPI path. Handlers call the same API resource and capability actions.

Staff register the client in Oauth. There is no Dynamic Client Registration.

## Install

1. Add the gem. Pin Recording Studio `~> 4.2`, API `~> 0.5.2`, Oauth `~> 0.1`.
2. Install and mount API and Oauth first. Allow `RecordingStudioOauth::OauthAuthorization` in Accessible `access_actor_types`.
3. Run `bin/rails generate recording_studio_mcp:install`.
4. Alias `/.well-known/oauth-protected-resource` to Oauth's metadata, as the Oauth dummy does.
5. Register a public PKCE OauthClient for the MCP app. People Connect. Then call MCP with the issued Bearer token.

Host authentication stays on the host. Dummy uses Devise. Do not add Users as a dependency of this gem.

This gem ships no product UI. Dummy host chrome may use Flatpack. Oauth owns Connect screens.

## Dummy

`test/dummy` on port 3000. Sign in with `admin@admin.com` / `Password`. Seed MCP App is a public OauthClient. Studio Workspace starts Connected. Site name `Studio` comes from Site settings when Connect needs it.

The dummy-only docs page at `/docs/mcp` shows the MCP URL. It is not the product.

## Version

0.1.0
