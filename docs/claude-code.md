# Claude Code

Point Claude Code at the host:

```bash
claude mcp add --transport http recording-studio \
  https://YOUR_HOST/recording_studio_mcp \
  --header "Authorization: Bearer YOUR_TOKEN"
```

Mint `YOUR_TOKEN` with the host Oauth flow ([Connect with OAuth](oauth.md)). Built-in tools list for every role on that server. Host-registered tools appear only on that host. Reconnect after a deploy when Claude Code ignores `notifications/tools/list_changed`.

Use `-N` / `--no-buffer` if you probe progress streams with curl. Proxies that buffer SSE will hide progress frames.
