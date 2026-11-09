---
title: Claude Code
description: Add the host MCP URL as a Streamable HTTP server.
---

Point Claude Code at the host, not at this docs site:

```bash
claude mcp add --transport http recording-studio \
  https://YOUR_HOST/recording_studio_mcp \
  --header "Authorization: Bearer YOUR_TOKEN"
```

Mint `YOUR_TOKEN` with the host Oauth flow ([Connect with OAuth](/oauth)). The grant decides which built-in tools appear. Host-registered tools appear only on that host.

Use `-N` / `--no-buffer` if you probe progress streams with curl. Proxies that buffer SSE will hide progress frames.
