# Introduction

Recording Studio MCP is a Streamable HTTP adapter. It speaks MCP. Domain writes still go through Recording Studio API. Access still goes through Accessible.

Hosts mount live docs with `recording_studio_mcp_docs_for`. That page reads the host catalog for the named API. Built-in tools:

- `list`, `show`, and `describe` for reading
- `create` and `update` for writing
- `capability_action` for named API capability actions. An optional `idempotency_key`, or the `Idempotency-Key` header, replays an action flagged `creates: true` when the input matches. A different input for that key is an error. Other actions ignore the key.
- `Recording` at `recording://{id}`. `resources/list` returns these in id order, 100 at a time. Follow `nextCursor` until a page leaves it out. Skill and UI resources are on the first page.

`delete` is also a built-in tool. It only appears when a type on that named API enables destroy. A host that enables destroy advertises it.

Type arguments, docs page names, and resource reads use a short public name. `RecordingStudioPresskits::PressKit` shows as `PressKit`, so an action page is `PressKit--set_embargo`. Callers may send that public name or the registered class name. `resolve_type!` maps both through the public-name catalog. That name is `registration.public_name`. A blank `public_name:` is the class name without its namespace. One named API cannot register two types with the same public name. Tool results use that public name for `type` and `recordable_type`. Nested items such as attachments and locations are managed through the parent type's actions (for example `add_image`), not as their own types. `describe` says that. An unregistered type string stays as the API sent it. An untitled resource name is the public name, a space, and the recording id. Call `describe` for the type paragraph, included tools, skills, and relationships.

JSON HTTP APIs stay on Scalar. This gem's docs page is MCP only.

Host apps register extra tools at runtime: endpoints, metrics, widgets, skills. Those show up on the mounted live page for that named API. The sidebar lists each tool tag once. `Overview` is first, then the remaining tags in alphabetical order, then `Other tools`. There is no Core group and no Tools group. Ping and the general tools sit under Overview. The Recording resource is not listed there. Capability actions appear as their own tool entries, still called through `capability_action`. That page ends with one `Tool:` line for the action. The idempotency sentence is included only when the action or its resource handler is flagged `creates: true`. Each type's allowed core tools (`list`, `show`, `create`, `update`, `delete`) are listed once on that type's group intro, and only the operations that type allows on the named API. A type with those operations and no capability action still has the group. A tag with no tools and no core lines is left out of the sidebar. An action summary and description use the per-type OpenAPI value when the gem sets one, and the shared action copy otherwise. Action pages and sidebar tags show the type description. Per-type schema components are not on this page. The Overview is the initialize text for that API, plus one line: a view-only connection gets the same text minus the Make changes part. A view-only connection receives the shorter text.
