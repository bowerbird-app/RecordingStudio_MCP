# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio_MCP/releases/tag/v0.1.0
