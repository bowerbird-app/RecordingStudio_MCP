Recording Studio MCP is mounted.

This gem is a protocol adapter. Mount Recording Studio API and Oauth first. Staff register the MCP app as an OauthClient. People Connect. MCP then authenticates Bearer tokens with `RecordingStudioApi.access_grant_from_authorization_header`. That Bearer intentionally works with both MCP and the client's named API through the same AccessGrant.

1. Review `config/initializers/recording_studio_mcp.rb`.
2. Alias `/.well-known/oauth-protected-resource` to Oauth's protected-resource metadata, the same way the Oauth dummy does.
3. Add any trusted cross-origin browser clients to `allowed_origins`. Native clients without `Origin` need no entry.
4. Point MCP clients at the mounted MCP URL. They should send the negotiated `MCP-Protocol-Version` after initialize.
