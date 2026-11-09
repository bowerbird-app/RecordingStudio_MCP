---
title: Cursor
description: Point Cursor at the host's Streamable HTTP MCP URL.
---

Add a server to Cursor MCP settings. Use the host URL, not this docs site.

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

Mint `YOUR_TOKEN` with the host Oauth flow ([Connect with OAuth](/oauth)). Cursor then lists the tools the grant can see.

This reference is generated from the gem's built-in snapshot. A Cursor session against a host will also see tools that host registered.
