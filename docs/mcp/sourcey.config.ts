import { defineConfig, markdown, mcp } from "sourcey";

export default defineConfig({
  name: "Recording Studio MCP",
  repo: "https://github.com/bowerbird-app/RecordingStudio_MCP",
  brokenLinks: "error",
  prettyUrls: "slash",
  footer: {
    text: "Example dummy snapshot. Built-in MCP tools only. Host apps mount live docs from the gem. JSON HTTP APIs stay on Scalar.",
  },
  navigation: {
    tabs: [
      {
        tab: "Guides",
        slug: "",
        source: markdown({
          groups: [
            {
              group: "Start",
              pages: ["introduction", "oauth", "cursor", "claude-code"],
            },
          ],
        }),
      },
      {
        tab: "MCP Reference",
        slug: "mcp",
        source: mcp({
          spec: "./server.snapshot.json",
          groups: {
            Reading: ["list", "show", "describe"],
            Writing: ["create", "update"],
            Capabilities: ["capability_action"],
            Resources: ["Recording"],
          },
        }),
      },
    ],
  },
});
