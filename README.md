# greentic-perf

`greentic-perf` is the bootstrap repository for Greentic end-to-end `gtc` performance testing. It is intended to grow into a runner + fixtures + policies repository that measures real CLI journeys, catches hangs, and tracks performance regressions without turning into another implementation repo.

The current repository includes the bootstrap layout plus the first pass of the reusable scenario runner crate under `perf/`. The root binary remains intentionally small, while the dedicated harness crate now contains subprocess execution, timeout handling, temp-workspace setup, machine-readable result serialization for end-to-end Greentic CLI scenarios over generated pack, bundle, and `.gtbundle` inputs, and an initial `gtc start` runtime harness for startup and Direct Line probing.

## Repository Layout

- `src/`: current root binary crate entrypoint.
- `perf/`: dedicated performance harness crate, plus benches and integration tests.
- `fixtures-src/`: checked-in canonical fixture answers.
- `fixtures-gen/`: generated pack workspaces, bundle workspaces, and packaged `.gtbundle` artifacts.
- `fixtures-gen/runtime/`: generated runtime bundle directories plus runtime `.gtbundle` artifacts.
- `docs/`: repository-level process and governance documentation.
- `scripts/`: helper scripts for future fixture and benchmark workflows.
- `ci/`: local CI entrypoints shared by developers and GitHub Actions.

Contributor guidance lives in [`docs/contribution-contract.md`](docs/contribution-contract.md).

## Development

Run the local CI wrapper from the repository root:

```bash
bash ci/local_check.sh
```

Run the heavier local perf matrix, including smoke/medium/heavy scenario JSON output and the nightly-style benchmark profile, with:

```bash
bash ci/perf_test.sh
```

Run the current Criterion benchmark suite from the harness crate with:

```bash
cargo bench -p greentic-perf-harness --bench cli_bench
```

Generate the current real fixture set with:

```bash
./scripts/generate_fixtures.sh
```

Generate the runtime startup bundle fixture with:

```bash
./scripts/generate_runtime_fixtures.sh
```

The current bootstrap acceptance target is simple:

- build on Rust `1.94`
- keep `cargo test` green
- keep a basic smoke workflow green on GitHub Actions

## Real Fixture Policy

Fixtures in this repo are generated real Greentic workspaces rather than JSON-only perf payloads.

Source of truth:

- `fixtures-src/<tier>/**/answers.json`

Generated outputs:

- `fixtures-gen/<tier>/packs/**`
- `fixtures-gen/<tier>/bundles/**`
- `fixtures-gen/<tier>/artifacts/**/*.gtbundle`

Tiers:

- `smoke`: smallest valid real fixture, suitable for PR CI
- `medium`: broader multi-pack fixture for regular e2e perf coverage
- `heavy`: larger stress fixture for nightly scaling and hang detection

The current non-runtime generator now follows the intended lifecycle more closely:

- `gtc wizard --answers ...` creates packs and bundles
- `gtc setup --answers ...` applies bundle setup/configuration
- packaged `.gtbundle` archives are built from the configured bundle workspaces

The runtime generator now follows the same top-level lifecycle too:

- `gtc wizard --answers ...` creates the runtime bundle workspace
- `gtc setup --answers ...` applies runtime setup answers
- `gtc start` runs the resulting bundle

The remaining runtime gap is now in the released `gtc start` behavior rather than wizard/setup generation. The generated runtime bundle does include a real `messaging-webchat.gtpack`, but the current released runtime still tries to launch `cloudflared` and wait for a public URL even when the local fixture disables public web hosting, so the richer Direct Line scenarios remain gated.

## Runtime Perf

Runtime perf coverage lives in the harness crate under `perf/src/runtime/` and starts real worker bundles with `gtc start`.

- `perf/src/runtime/start.rs` launches and manages the worker process.
- `perf/src/runtime/readiness.rs` waits for runtime state artifacts and a reachable ingress listener.
- `perf/src/runtime/directline.rs` drives the built-in webchat Direct Line surface with polling.
- `perf/src/runtime/metrics.rs` provides machine-readable startup and latency summaries.

The current runtime fixture source is:

- `fixtures-src/runtime/qa-template-worker/answers.json`

The current bootstrap runtime test is:

- `cargo test -p greentic-perf-harness --test runtime_startup`

The Direct Line single-turn and multi-turn tests are checked in but still marked ignored until the released `gtc start` path respects the local-only runtime fixture and keeps the runtime alive without forcing a cloudflared tunnel. Design notes live in [`docs/runtime-perf.md`](docs/runtime-perf.md).

## Tooling Policy

`greentic-perf` validates against the latest released Greentic CLI toolchain by default in perf workflows and no longer uses a fake CLI fallback in the perf-critical test, example, and benchmark paths.

Install the latest released `gtc` with:

```bash
cargo binstall gtc --no-confirm
```

Refresh the latest installable Greentic artifacts with:

```bash
gtc install
```

Do not pin older versions in default workflows unless a compatibility or branch-specific job is being added intentionally.

## CI and Releases

The repository uses a single local entrypoint and matching GitHub Actions workflows:

- `ci/local_check.sh` runs formatting, clippy, tests, build, docs, and publish dry-run checks.
- `ci/perf_test.sh` bootstraps the latest released Greentic CLI toolchain, generates smoke/medium/heavy fixtures plus the runtime startup bundle, runs the heavier local scenario matrix, validates perf budgets, validates runtime startup, and executes the nightly-style benchmark profile.
- `.github/workflows/ci.yml` runs `lint`, `test`, and `package-dry-run` jobs for pull requests and pushes.
- `.github/workflows/smoke.yml` provides a minimal bootstrap smoke workflow that validates the pinned toolchain and runs `cargo test`.
- `.github/workflows/publish.yml` verifies the repository, checks that the Git tag matches the crate version, performs a mandatory crates.io dry run, and then publishes to crates.io.

Release flow:

1. Update the version in `Cargo.toml`.
2. Run `bash ci/local_check.sh`.
3. Create and push a tag in the form `vX.Y.Z`.
4. Ensure the `CARGO_REGISTRY_TOKEN` secret is configured in GitHub Actions.

The publish workflow currently targets crates.io only. `cargo-binstall`, GHCR publishing, and i18n automation are intentionally not enabled in this repo scaffold.
