# Introduction

Recording Studio MCP is a Streamable HTTP adapter. It speaks MCP. Domain writes still go through Recording Studio API. Access still goes through Accessible.

Hosts mount live docs with `recording_studio_mcp_docs_for`. That page reads the host catalog for the named API. Built-in tools:

- `list`, `show`, and `describe` for reading
- `create` and `update` for writing
- `capability_action` for named API capability actions. An optional `idempotency_key`, or the `Idempotency-Key` header, returns the first result for that action, type, and record.
- `Recording` at `recording://{id}`. `resources/list` returns these in id order, 100 at a time. Follow `nextCursor` until a page leaves it out. Skill and UI resources are on the first page.

`delete` is also a built-in tool. It only appears when a type on that named API enables destroy. A host that enables destroy advertises it.

Type arguments, docs tool names, and resource reads use a short public name. `RecordingStudioPresskits::PressKit` shows as `PressKit`, so an action page is `PressKit--set_embargo`. A full class name is rejected. Callers send the public name. That name is `registration.public_name`. A blank `public_name:` is the class name without its namespace. One named API cannot register two types with the same public name. Tool results use that public name for `type` and `recordable_type`. Nested items such as attachments and locations are managed through the parent type's actions (for example `add_image`), not as their own types. `describe` says that. An unregistered type string stays as the API sent it. An untitled resource name is the public name, a space, and the recording id. `describe` keeps nested field schema on writable fields.

JSON HTTP APIs stay on Scalar. This gem's docs page is MCP only.

Host apps register extra tools at runtime: endpoints, metrics, widgets, skills. Those show up on the mounted live page for that named API. The sidebar lists each tool tag once, in alphabetical order. There is no Core group. The general tools are explained in the Overview and are not sidebar entries. The Recording resource is not listed there. Capability actions appear as their own tool entries, still called through `capability_action`. An action summary and description use the per-type OpenAPI value when the gem sets one, and the shared action copy otherwise. Action pages and sidebar tags show the type description. Per-type schema components are not on this page. The Overview is the same text agents receive as initialize instructions for that API.
