# Cursor

Add a server to Cursor MCP settings. Use the host URL.

```json
{
  "mcpServers": {
    "recording-studio": {
      "url": "https://YOUR_HOST/recording_studio_mcp",
      "headers": {
        "Authorization": "Bearer YOUR_TOKEN"
      }
    }
  }
}
```

Mint `YOUR_TOKEN` with the host Oauth flow ([Connect with OAuth](oauth.md)). Cursor lists every tool that server includes. Reconnect after a deploy when Cursor ignores `notifications/tools/list_changed`.

A Cursor session against a host also sees tools that host registered.
