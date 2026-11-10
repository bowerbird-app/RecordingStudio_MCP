# Vendored Redoc CE 3.1.0

MIT. Copied from the `redoc@3.1.0` npm package (`bundles/redoc.standalone.js` and `LICENSE`).

The standalone bundle is an ES module. Hosts must not load Redoc from a CDN.

This copy has local-only asset URLs:

- Icon pack bases that pointed at `cdn.redocly.com` are blank, so icons do not fetch off-host.
- Attribution logos load from sibling `logo-mini.svg` and `logo-mini-full.svg` (copied from Redoc's CDN once at vendor time).
- The OpenTelemetry collector URL is blank. Live pages also set `disableTelemetry: true`.
