# Host pins

Ruby 3.3 or newer. Rails 8.1. Recording Studio `~> 4.2`. API `~> 0.5.4`. Oauth `~> 0.1`.

## 0.3.1

Optional `config.instructions_suffix` (String or `->(access_grant:) { ... }`). Richer default endpoint initialize blurb. No OAuth, tool, or connect changes. Hosts that want product-specific MCP guidance set the suffix.

## 0.3.0

Pin API to `~> 0.5.4`. That release owns `register_endpoint` and `RegisteredEndpointContext`.

MCP now builds a tool surface from the OauthClient's named API:

- Recordable types present: advertise the six tree tools.
- Registered endpoints present: advertise one tool per endpoint name.
- Both: tree tools first, then endpoint tools sorted by name.
- Neither: `tools/list` is empty. Initialize still explains the Bearer grant.

Catalog-only hosts stop seeing `list` / `describe` with an empty type enum. Clients must call the endpoint tools directly. Path tokens are tool arguments.

Do not register an endpoint named `list`, `show`, `create`, `update`, `capability_action`, or `describe`. MCP raises `RecordingStudioApi::ConfigurationError` if those collide.

`tools/call` for a GET endpoint is a read for API rate limiting, same as `list`, `show`, and `describe`.

## 0.2.1

Dummy-only “Try MCP” and “Sample POST” on `/docs/mcp`. No host upgrade required.

Dummy GitHub tags used to prove Connect then MCP:

- Recording Studio `v4.2.1`
- Accessible `v0.9.1`
- API `v0.5.4`
- Oauth `v0.1.0`
- Admin `v2.0.2`
- Site settings `v0.1.0`
- Attachable `v0.5.1`
- Flatpack `v0.1.144`

Dummy stays on Devise. This gem does not depend on Users.

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```
