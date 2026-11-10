# Vendored Redoc CE 3.1.0

MIT. Copied from the `redoc@3.1.0` npm package (`bundles/redoc.standalone.js` and `LICENSE`). See `THIRD_PARTY` for bundled licenses.

The standalone bundle is an ES module. Hosts must not load Redoc from a CDN.

## Upgrade

From the gem root:

```sh
bin/vendor-redoc 3.1.0
```

The version must be `3.1.x`. The script fetches the npm tarball, copies `LICENSE`, downloads the attribution logos, blanks CDN icon bases and the OpenTelemetry collector URL, and replaces logo URLs with `redoc-logo-mini.local` / `redoc-logo-mini-full.local`. The docs controller rewrites those to `{mount}/logo-mini.svg` and `{mount}/logo-mini-full.svg`.

Do not edit `redoc.standalone.js` by hand. Re-run the script.

Live pages also set `disableTelemetry: true`.
