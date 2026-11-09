---
title: Introduction
description: What this MCP reference covers, and what it leaves out.
---

Recording Studio MCP is a Streamable HTTP adapter. It speaks MCP. Domain writes still go through Recording Studio API. Access still goes through Accessible. This site is the **example dummy snapshot** of the built-in tools that adapter ships. A host's live types belong on the gem-owned docs page, not here.

- `list`, `show`, and `describe` for reading
- `create` and `update` for writing
- `capability_action` for named API capability actions
- `Recording` at `recording://{id}`

`delete` is also a built-in tool. It only appears on `tools/list` when a type on that named API enables destroy. The dummy app used for this snapshot does not, so `delete` is not in the reference. A host that enables destroy will advertise it, with a destructive badge.

JSON HTTP APIs stay on **Scalar**. This site is MCP only.

Host apps register extra tools at runtime: endpoints, metrics, widgets, skills. Those do not appear here. Snapshot the running host if you need that surface.
