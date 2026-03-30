# Fixture Model

`greentic-perf` now uses a two-layer fixture model.

## Source Fixtures

Checked-in source fixture answers live under:

- `fixtures-src/**/answers.json`

These files are the canonical editable inputs for the current generated fixture flow.

## Generated Fixtures

Derived outputs live under:

- `fixtures-gen/<tier>/packs/**`
- `fixtures-gen/<tier>/bundles/**`
- `fixtures-gen/<tier>/artifacts/**/*.gtbundle`

The generated outputs are real pack workspaces, bundle workspaces, and packaged `.gtbundle` archives.

## Rule

Perf scenarios should consume generated real pack or bundle workspaces rather than ad-hoc JSON-only fixture payloads.

## Why

Synthetic JSON blobs bypass the filesystem layout, bundle assembly, and package-archive paths that real `gtc` users exercise. Generated fixtures keep the repo deterministic while moving perf coverage closer to real CLI usage.

## Current Generator

The current generator is implemented in `scripts/generate_fixtures.sh` and follows the intended lifecycle for standard fixture bundles:

- `gtc wizard --answers ...` to create packs and bundles
- `gtc setup --answers ...` to configure bundles
- bundle build/package commands to produce `.gtbundle` artifacts

GitHub perf workflows bootstrap the latest released `gtc` first so fixture generation and workflow e2e runs track the current released CLI by default.

The runtime fixture now follows the same top-level lifecycle too: `gtc wizard --answers ...` creates the bundle, `gtc setup --answers ...` configures it, and `gtc start` runs it. The remaining runtime limitation is no longer the fixture generator; it is the released `gtc start` behavior that still tries to force a cloudflared/public-url flow for the local-only runtime bundle.
