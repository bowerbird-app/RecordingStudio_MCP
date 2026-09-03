Recording Studio MCP is mounted.

This gem is a protocol adapter. Mount Recording Studio API and Oauth first. Staff register the MCP app as an OauthClient. People Connect. MCP then authenticates Bearer tokens with `RecordingStudioApi.access_grant_from_authorization_header`.

1. Review `config/initializers/recording_studio_mcp.rb`.
2. Alias `/.well-known/oauth-protected-resource` to Oauth's protected-resource metadata, the same way the Oauth dummy does.
3. Point MCP clients at the mounted MCP URL.
