# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-09-10

### Added
- Optional `config.instructions_suffix`. A String or `->(access_grant:) { ... }` is appended after the built-in initialize instructions.

### Changed
- Endpoint initialize text now teaches `tools/list`, names the endpoint-only grant, and tells clients to fetch item detail before generating UI.

### Upgrade notes
- Optional `config.instructions_suffix` (String or `->(access_grant:) { ... }`). Richer default endpoint initialize blurb. No OAuth, tool, or connect changes. Hosts that want product-specific MCP guidance set the suffix.

## [0.3.0] - 2026-09-09

### Added
- One MCP tool per `RecordingStudioApi.register_endpoint` entry. Tool name matches the endpoint name. Path tokens and `input_contract` fields become the tool `inputSchema`.
- Dynamic initialize instructions from the grant's tool surface.

### Changed
- Tree tools (`list`, `show`, `create`, `update`, `capability_action`, `describe`) appear only when the named API has recordable types.
- Catalog-only hosts no longer advertise empty tree tools.
- Mixed hosts list tree tools first, then endpoint tools sorted by name.
- `tools/call` for a GET registered endpoint counts as a read for API rate limiting.

### Upgrade notes
- Pin `recording_studio_api` to `~> 0.5.4`.
- Catalog-only hosts now see endpoint tools on `tools/list`. Clients that assumed the six tree names always exist need to read the advertised list.
- Tree tools are omitted when the named API has no recordable types. Do not tell those clients to call `describe` before create.
- Do not `register_endpoint` with a tree tool name. MCP raises a configuration error if an endpoint is named `list`, `show`, `create`, `update`, `capability_action`, or `describe`.

## [0.2.1] - 2026-09-07

### Added
- Dummy-only “Try MCP” and “Sample POST” on `/docs/mcp`: mint a Seed MCP App token, probe MCP, then prove the Bearer grant resolves through the same post-auth MCP path (without nesting a full inner HTTP request that resets Current).

### Upgrade notes
- Dummy-only helper. No host upgrade required.

## [0.2.0] - 2026-09-07

### Added
- Initialize instructions that teach clients to describe types before writes, use top-level fields, and follow pagination tokens.
- Typed writable-field details and capability action input contracts in `describe`.
- Explicit tool titles plus read-only, destructive, idempotent, and closed-world (`openWorldHint: false`) annotations.
- Origin allowlisting and `MCP-Protocol-Version` validation for Streamable HTTP requests.

### Changed
- Report `tools.listChanged: false` because this endpoint does not send live tool-list updates.
- Clarify that the Oauth Bearer intentionally works with both MCP and its named API through the same AccessGrant.

### Upgrade notes
- `describe.writable_fields` now contains field objects instead of field-name strings. Read each object's `name`, `required`, `type`, optional `allowed_values`, and optional `immutable_on_update`.
- Browser clients with a cross-origin MCP connection must add their exact origin to `allowed_origins`. Native clients without an `Origin` header continue to work.
- Send the negotiated `MCP-Protocol-Version` after initialize. Missing headers use the MCP `2025-03-26` backwards-compatible default; unsupported versions return `400`.

## [0.1.0] - 2026-09-03

### Added
- Mountable engine with a remote Streamable HTTP MCP endpoint.
- Unauthenticated calls return `401` with `WWW-Authenticate` pointing at Oauth RFC 9728 protected-resource metadata.
- Bearer authentication through `RecordingStudioApi.access_grant_from_authorization_header`.
- Authorization through the same Accessible AccessGrant as API.
- Parameterized tools `list`, `show`, `create`, `update`, `capability_action`, and `describe` over the named API the OauthClient is bound to.
- Grant-aware `tools/list` with a `type` enum, `listChanged: true`, and `structuredContent` on tool results.
- Create and update take writable fields at the request root. `list` accepts `pagination_token`.
- Dummy host that stacks Oauth + API + MCP, seeds a public PKCE client, and proves Connect then a tool call.

### Upgrade notes
- First release. Mount after API and Oauth. Register the MCP app as an OauthClient. Do not add a second authorization server.

[0.3.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.3.0
[0.2.1]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.2.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.1.0
