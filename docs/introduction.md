# Introduction

Recording Studio MCP is a Streamable HTTP adapter. It speaks MCP. Domain writes still go through Recording Studio API. Access still goes through Accessible.

Hosts mount live docs with `recording_studio_mcp_docs_for`. That page reads the host catalog for the named API. Built-in tools:

- `list`, `show`, and `describe` for reading
- `create` and `update` for writing
- `capability_action` for named API capability actions
- `Recording` at `recording://{id}`

`delete` is also a built-in tool. It only appears when a type on that named API enables destroy. A host that enables destroy advertises it.

Type arguments, docs tool names, and resource reads use a short public name. `RecordingStudioPresskits::PressKit` shows as `PressKit`, so an action page is `PressKit--set_embargo`. A full class name is rejected. Callers send the public name. That name is `registration.public_name`. A blank `public_name:` is the class name without its namespace. One named API cannot register two types with the same public name.

JSON HTTP APIs stay on Scalar. This gem's docs page is MCP only.

Host apps register extra tools at runtime: endpoints, metrics, widgets, skills. Those show up on the mounted live page for that named API. The sidebar lists each tool tag once. Capability actions appear as their own tool entries, still called through `capability_action`. Action pages and sidebar tags show the type description. Per-type schema components are not on this page. The overview is written for people. Agent instructions stay on the MCP session.
