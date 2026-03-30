# Runtime Perf

`greentic-perf` now includes the first runtime-oriented harness pieces for `gtc start`.

## Current Scope

- generate a runtime bundle fixture under `fixtures-gen/runtime/`
- start the bundle with `gtc start`
- capture runtime state and log artifacts
- probe the built-in webchat Direct Line surface with polling clients

## Current Status

What is active today:

- runtime fixture generation via `scripts/generate_runtime_fixtures.sh`
- startup validation in `perf/tests/runtime_startup.rs`
- reusable runtime harness code in `perf/src/runtime/`

What is checked in but still intentionally gated:

- Direct Line single-turn test
- stateful two-turn runtime test
- concurrency runtime scenarios

Those tests remain ignored until the released `gtc start` path keeps the local-only runtime fixture alive without forcing a cloudflared tunnel.

## Why The Gating Exists

The harness now uses the real released `gtc` runtime entrypoint, and the runtime fixture itself follows the same high-level lifecycle as the standard fixtures: `gtc wizard --answers ...` creates the bundle workspace and `gtc setup --answers ...` applies setup answers before `gtc start` runs it. The repo keeps the startup path active so `gtc start` regressions are visible immediately, while the richer messaging scenarios are kept checked in and ready to enable once the runtime stays up reliably for local Direct Line traffic.

The remaining blocker is the released runtime behavior, not provider availability or the wizard/setup flow. The generated runtime bundle now contains a real `messaging-webchat.gtpack`, and the Direct Line client has been updated to probe the provider's documented `/v3/directline/...` contract first. The current released `gtc start` path still synthesizes a `cloudflared` launch and times out waiting for a public URL even when the local fixture disables public web hosting, so the runtime does not stay available long enough for end-to-end Direct Line validation.

## Intended Next Step

Enable the Direct Line scenarios by making the runtime fixture generator land a bundle that exposes:

- `POST /v3/directline/tokens/generate`
- `POST|GET /v3/directline/conversations/...`

Once the released runtime honors the local-only setup and keeps those routes live, the ignored runtime tests should move onto the regular PR/nightly perf path.
