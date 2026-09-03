# Host pins

Ruby 3.3 or newer. Rails 8.1. Recording Studio `~> 4.2`. API `~> 0.5.2`. Oauth `~> 0.1`.

Dummy GitHub tags used to prove Connect then MCP:

- Recording Studio `v4.2.1`
- Accessible `v0.9.1`
- API `v0.5.2`
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
