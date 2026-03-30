# Smoke Fixture Tier

This fixture tier is intentionally small and deterministic. It models the smallest useful pack/bundle-style workspace that a `gtc` smoke run could inspect quickly.

Contents:

- `workspace.json`: high-level fixture metadata.
- `packs/core/pack.json`: a tiny pack manifest.
- `bundles/smoke-bundle.json`: a minimal bundle description.
- `assets/messages/en.txt`: small local asset content.

The current smoke tests and benchmarks copy this directory into a temporary workspace before launching the test binary.
