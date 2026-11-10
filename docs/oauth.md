# Connect with OAuth

People Connect an OauthClient. The app gets its own Accessible grant. MCP uses that grant. The app does not act as the person.

Unauthenticated calls return `401` with `WWW-Authenticate` pointing at MCP's protected-resource metadata:

`/.well-known/oauth-protected-resource/recording_studio_mcp`

That document sets `resource` to the MCP URL and `authorization_servers` to Oauth. Clients authorize with authorization-code + PKCE S256 against Oauth (`/oauth/authorize`). Token exchange stays on API:

`POST /recording_studio_api/oauth/token`

Call MCP with `Authorization: Bearer <token>`. The same Bearer works for that named API and that MCP path on purpose.

Staff register the client in Oauth. There is no Dynamic Client Registration in the gem. The dummy app can turn self-registration on for Inspector.

A view grant sees read tools. Create, update, and delete need edit. `describe` stays when the API has types.

Do not commit tokens.
