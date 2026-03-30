# Repository Overview

## 1. High-Level Purpose

`greentic-perf` is a Rust-based Greentic repository for end-to-end `gtc` performance validation. Its role is to run CLI journeys against deterministic fixture workspaces, capture timing and failure information, and provide the policies and automation needed to catch regressions and hangs over time.

The repository now includes a generated-fixture pipeline in addition to the harness, budgets, benchmarks, and workflows built in earlier PRs. Canonical fixture answers live in `fixtures-src/`, generated pack and bundle workspaces plus `.gtbundle` artifacts are materialized under `fixtures-gen/`, and the perf workflows now default to bootstrapping the latest released `gtc` before running the workflow e2e paths. The main fixture generator now uses top-level `gtc wizard apply` launcher documents to drive the underlying pack and bundle wizards rather than calling those delegated CLIs directly. The repo also now has its first `gtc start` runtime harness pieces: a generated runtime bundle fixture, a startup probe, and a Direct Line client scaffold for future runtime messaging benchmarks.

## 2. Main Components and Functionality

- **Path:** `perf/src/scenario.rs`
  - **Role:** Core subprocess scenario runner.
  - **Key functionality:**
    - Exposes `run_scenario(...)` with the shared API used across tests, examples, and benchmarks.
    - Resolves the program under test from `RepoRef::Path(...)`, `GREENTIC_PERF_BIN`, `GTC_BIN`, or the named Greentic CLI on `PATH`.
    - Copies the supplied fixture into a temporary workspace before execution.
    - Applies a thread override with the `GTC_THREADS` environment variable.
    - Polls child-process completion, kills timed-out runs, captures stdout/stderr tails, and records phase markers such as `fixture_prep`, `command_start`, `command_end`, and `timeout`.
  - **Key dependencies / integration points:**
    - Used by smoke tests, budget validation, benchmarks, and workflow examples.

- **Path:** `perf/src/result.rs`
  - **Role:** Machine-readable scenario result model.
  - **Key functionality:**
    - Defines `ScenarioResult`, `ScenarioCommand`, and `ScenarioPhase`.
    - Stores command metadata, paths, timeout and wall-time values, output tails, `last_completed_phase`, and the ordered phase timeline.
    - Produces pretty-printed JSON for artifact collection and diagnostics.
  - **Key dependencies / integration points:**
    - Serialized by the example runners and asserted by tests.

- **Path:** `perf/examples/scenario_json.rs` and `perf/examples/criterion_summary.rs`
  - **Role:** Workflow-facing helper commands.
  - **Key functionality:**
    - Generate machine-readable scenario JSON artifacts.
    - Summarize Criterion results into markdown for workflow summaries.
    - Select the real binary under test from `GREENTIC_PERF_BIN`, `GTC_BIN`, or `gtc` on `PATH`.
  - **Key dependencies / integration points:**
    - Used by the PR and nightly perf workflows.

- **Path:** `perf/src/runtime/`
  - **Role:** Runtime-oriented harness for `gtc start` scenarios.
  - **Key functionality:**
    - `start.rs` launches `gtc start <bundle>` as a subprocess, captures stdout and stderr logs, and manages process shutdown.
    - `readiness.rs` waits for runtime state files and platform config so startup tests can distinguish "process spawned" from "runtime ready".
    - `directline.rs` contains a blocking Direct Line polling client for conversation creation, message send, and reply polling, preferring the provider pack's `/v3/directline/...` contract while keeping legacy route fallbacks.
    - `metrics.rs` defines structured runtime metrics and percentile summaries for future latency and throughput reporting.
  - **Key dependencies / integration points:**
    - Used by the runtime tests and intended to back future runtime perf workflow artifacts.

- **Path:** `perf/tests/`
  - **Role:** Harness, smoke, and policy validation.
  - **Key functionality:**
    - `scenario_runner.rs` validates runner behavior, timeout handling, and phase diagnostics.
    - `smoke_cli.rs` and `smoke_threads.rs` cover real `gtc`, `greentic-dev`, and `greentic-bundle` smoke command flows and thread-count variants.
    - `perf_budgets.rs` parses `perf-budgets.yaml` and enforces success, timeout, wall-time, and scaling policy for generated pack, bundle, and `.gtbundle` scenarios.
    - `fixtures_real.rs` validates that all generated pack, bundle, and `.gtbundle` outputs exist for smoke, medium, and heavy tiers.
    - `runtime_startup.rs` validates that a generated runtime bundle can be started with `gtc start` and stays alive after startup.
    - `runtime_single_turn.rs`, `runtime_two_turn.rs`, and `runtime_concurrency.rs` check in the intended Direct Line runtime scenarios but keep them ignored until a real messaging-webchat provider pack can be resolved reliably in generated runtime fixtures.
  - **Key dependencies / integration points:**
    - Generate `fixtures-gen/` via `scripts/check_fixtures.sh` before using generated fixture paths.
    - Require the latest released Greentic CLIs to be available on `PATH`.

- **Path:** `perf-budgets.yaml`
  - **Role:** Declarative performance budget policy.
  - **Key functionality:**
    - Defines smoke-tier scenarios, target binaries, arguments, generated fixture paths, per-thread max wall-time budgets, and scaling thresholds.
    - Currently covers `greentic-dev pack build`, `greentic-bundle build`, and `.gtbundle` inspection smoke scenarios.
    - Uses looser scaling thresholds for the tiny smoke `pack build` and `bundle build` cases because the latest released CLIs show large relative variance on such short runs even while absolute wall time stays low.
  - **Key dependencies / integration points:**
    - Read by `perf/tests/perf_budgets.rs`.

- **Path:** `perf/benches/cli_bench.rs`
  - **Role:** Criterion benchmark suite for CLI-style scenario execution.
  - **Key functionality:**
    - Benchmarks `greentic-dev pack build`, `greentic-bundle build`, and `greentic-bundle inspect --artifact ... --json --offline` journeys via the shared runner against generated pack, bundle, and `.gtbundle` inputs.
    - Uses `GREENTIC_BENCH_PROFILE` to switch between the fast PR matrix and the broader nightly matrix.
    - Writes benchmark output under `target/criterion/` and supports baseline comparisons.
  - **Key dependencies / integration points:**
    - Resolves the named released binaries directly from `PATH`.

- **Path:** `fixtures-src/`, `fixtures-gen/`, and `scripts/generate_fixtures.sh`
  - **Role:** Canonical answers plus generated real fixture outputs.
  - **Key functionality:**
    - Keep source-of-truth fixture answers in `fixtures-src/<tier>/**/answers.json`.
    - Materialize generated pack workspaces, bundle workspaces, and packaged `.gtbundle` archives under `fixtures-gen/`.
    - Build launcher answer documents and drive pack and bundle creation through top-level `gtc wizard apply`, then apply bundle setup via `gtc setup --answers ...`, then add deterministic extra files to scale smoke, medium, and heavy tiers.
    - Accept explicit tier arguments and automatically include prerequisite lower tiers when generating `medium` or `heavy`.
  - **Key dependencies / integration points:**
    - Used by `scripts/check_fixtures.sh`, `ci/local_check.sh`, tests, benches, and perf workflows.

- **Path:** `fixtures-src/runtime/` and `scripts/generate_runtime_fixtures.sh`
  - **Role:** Runtime-bundle source answers plus generated `gtc start` fixture output.
  - **Key functionality:**
    - Defines the runtime fixture source for `qa-template-worker`.
    - Generates `fixtures-gen/runtime/bundles/qa-template-worker/` via top-level `gtc wizard --answers ...`, applies runtime setup with `gtc setup --answers ...`, and builds `fixtures-gen/runtime/artifacts/qa-template-worker.gtbundle`.
    - Normalizes the runtime build output even when `gtc setup bundle build` writes a directory-shaped artifact workspace rather than a bare `.gtbundle` file.
    - Cleans up stale local runtime tunnel artifacts before promoting the generated bundle into `fixtures-gen/runtime/`.
  - **Key dependencies / integration points:**
    - Used by runtime tests, `ci/perf_test.sh`, and the perf workflows.

- **Path:** `scripts/bootstrap_gtc.sh`
  - **Role:** Latest-release CLI bootstrap for perf workflows and local opt-in use.
  - **Key functionality:**
    - Installs `cargo-binstall` if needed.
    - Installs the latest released `gtc` with `cargo binstall gtc --no-confirm`.
    - Runs `gtc install`, using `GREENTIC_TENANT` when supplied.
  - **Key dependencies / integration points:**
    - Called by the perf GitHub workflows and exposed via `make bootstrap`.

- **Path:** `fixtures/`
  - **Role:** Older tracked deterministic fixture snapshot.
  - **Key functionality:**
    - Preserves the earlier static fixture tiers and README descriptions.
  - **Key dependencies / integration points:**
    - No longer the primary input for perf tests, budgets, or workflow e2e paths.

- **Path:** `.github/workflows/perf-pr.yml` and `.github/workflows/perf-nightly.yml`
  - **Role:** Perf-specific CI automation.
  - **Key functionality:**
    - `perf-pr.yml` bootstraps the latest released `gtc` in every job, generates smoke fixtures plus the runtime fixture, runs smoke tests against the real installed CLIs, includes the active runtime startup test, emits scenario JSON for real pack and `.gtbundle` cases, and runs the small benchmark matrix.
    - `perf-nightly.yml` bootstraps the latest released `gtc`, generates smoke/medium/heavy fixtures plus the runtime fixture, runs the wider scenario matrix including `.gtbundle` inspection, and publishes a markdown performance summary.
  - **Key dependencies / integration points:**
    - Depend on the bootstrap script, generated fixtures, example commands, and benchmark suite rather than duplicating runner logic in shell.

- **Path:** `ci/perf_test.sh`
  - **Role:** Local heavy perf wrapper aligned with the nightly workflow.
  - **Key functionality:**
    - Bootstraps the latest released Greentic CLI toolchain via `scripts/bootstrap_gtc.sh`.
    - Generates smoke, medium, and heavy fixtures plus the runtime fixture.
    - Runs the perf budget test plus the heavier local scenario matrix and writes JSON/log artifacts under `artifacts/perf-local/`.
    - Runs the active runtime startup test in addition to the CLI perf checks.
    - Executes the nightly benchmark profile and writes a local markdown summary.
  - **Key dependencies / integration points:**
    - Mirrors the main scenario coverage from `.github/workflows/perf-nightly.yml`.

- **Path:** `ci/local_check.sh`, `.github/workflows/ci.yml`, `.github/workflows/smoke.yml`, and `.github/workflows/publish.yml`
  - **Role:** Baseline local, smoke, and release validation.
  - **Key functionality:**
    - Run formatting, clippy, tests, build, docs, package verification, and crates.io dry runs.
    - Keep the publishable root crate healthy independently of the perf-specific workflows.
  - **Key dependencies / integration points:**
    - Complement the perf-specific workflows rather than replacing them.

- **Path:** `docs/contribution-contract.md` and `docs/README.md`
  - **Role:** Repository governance and contribution contract.
  - **Key functionality:**
    - Document what belongs in `greentic-perf` and what does not.
    - Explain how to add fixtures and scenarios.
    - Describe how to set budgets, interpret regressions, and choose between PR smoke and nightly coverage.
    - Establish repo-cleanliness rules so code, fixtures, policies, and docs evolve together.
  - **Key dependencies / integration points:**
    - Linked from `README.md` and intended to guide future PRs and contributor decisions.

- **Path:** `README.md`, `docs/fixtures.md`, `docs/runtime-perf.md`, and `Makefile`
  - **Role:** Human-facing fixture and tooling guidance.
  - **Key functionality:**
    - Document the generated real fixture policy and latest-`gtc` tooling policy.
    - Document the current runtime-perf scope, including what is active and what remains gated.
    - Provide local entrypoints for `bootstrap`, `fixtures`, `runtime-fixtures`, and the full local check.
  - **Key dependencies / integration points:**
    - Keep the local developer workflow aligned with the perf CI workflows.

- **Path:** `.codex/`
  - **Role:** Codex-facing maintenance documentation.
  - **Key functionality:**
    - Stores the repo overview, maintenance routine, workflow rules, and staged implementation roadmap.
  - **Key dependencies / integration points:**
    - Updated before and after PR-style work.

## 3. Work In Progress, TODOs, and Stubs

- **Location:** Repository-wide marker scan
  - **Status:** No explicit TODO markers found
  - **Short description:** A scan for `TODO`, `FIXME`, `XXX`, `HACK`, `BROKEN`, `TEMP`, `todo!`, `unimplemented!`, `unimplemented`, and similar markers did not find literal markers in the current tracked files.

- **Location:** `src/main.rs:1`
  - **Status:** Stub
  - **Short description:** The publishable root binary still only prints a bootstrap message; the real performance behavior remains in the internal harness crate.

- **Location:** `fixtures-src/runtime/qa-template-worker/answers.json` and `scripts/generate_runtime_fixtures.sh`
  - **Status:** Partial
  - **Short description:** The first runtime fixture now creates a real bundle and artifact plus a real `messaging-webchat.gtpack`, but the richer Direct Line scenarios remain gated because the released `gtc start` path still forces a cloudflared-style public URL flow for this local fixture.

- **Location:** `perf/tests/runtime_single_turn.rs`, `perf/tests/runtime_two_turn.rs`, `perf/tests/runtime_concurrency.rs`
  - **Status:** Stub / gated
  - **Short description:** The runtime Direct Line scenarios are implemented structurally and compile, but they are `#[ignore]`d until generated runtime fixtures expose a stable messaging endpoint in local and CI environments.

## 4. Broken, Failing, or Conflicting Areas

- **Location:** `ci/local_check.sh`
  - **Evidence:** After relaxing the smoke `.gtbundle` inspect scaling threshold to match the already-loosened smoke build scenarios, `bash ci/local_check.sh` passes with workspace clippy, generated fixture validation, workspace tests, build, docs, package verification, and `cargo publish --dry-run`.
  - **Likely cause / nature of issue:** The remaining runtime Direct Line issue is still gated in ignored tests, so the mainline repository check remains green while that upstream runtime behavior is investigated.

- **Location:** `scripts/bootstrap_gtc.sh` and perf workflows
  - **Evidence:** The workflows now default to `cargo binstall gtc --no-confirm` plus `gtc install`, but that path was only validated structurally in-code, not exercised from this local sandbox.
  - **Likely cause / nature of issue:** Installing the latest released CLI and installable artifacts requires networked GitHub Actions or an equivalent environment; the local sandbox cannot fully validate that live path here.

- **Location:** `gtc wizard --answers ...` launcher path
  - **Evidence:** Launcher validation succeeds when the document uses `wizard_id: greentic-dev.wizard.launcher.main` together with `schema_id: greentic-dev.launcher.main`; using the older schema ID form still fails.
  - **Likely cause / nature of issue:** The released launcher identity is stricter than earlier experiments implied, so launcher documents must use the corrected schema ID even though the delegated workflows themselves work.

- **Location:** `.github/workflows/perf-pr.yml`
  - **Evidence:** The PR perf workflow installs the latest released toolchain in each job and does not build or use a branch-local `gtc`.
  - **Likely cause / nature of issue:** This is an intentional released-tooling mode, but it means PR perf validates the latest release rather than the branch's unpublished CLI bits.

- **Location:** `scripts/generate_runtime_fixtures.sh`, `perf/src/runtime/directline.rs`, and `docs/runtime-perf.md`
  - **Evidence:** Runtime fixture generation now lands a real `providers/messaging/messaging-webchat.gtpack`, and the Direct Line client now probes the provider pack's documented `/v3/directline/...` routes first; however, `gtc start fixtures-gen/runtime/bundles/qa-template-worker ...` still exits with `timed out waiting for cloudflared public URL ...` even when `state/config/platform/static-routes.json` says `public_web_enabled: false`.
  - **Likely cause / nature of issue:** The current released `gtc start` path appears to force a cloudflared/public-url flow for this local runtime fixture even after setup disables public web hosting, so the richer Direct Line runtime scenarios remain gated by upstream runtime behavior rather than missing provider generation.

- **Location:** `scripts/generate_fixtures.sh` bundle setup phase
  - **Evidence:** `gtc setup --answers ...` on launcher-created bundle fixtures emits `Create demo bundle scaffold using existing conventions` and adds `greentic.demo.yaml` plus `packs/default.gtpack` even for the standard smoke/medium/heavy bundle fixtures.
  - **Likely cause / nature of issue:** The current released `gtc setup` path appears to apply demo-bundle conventions broadly rather than acting as a narrow “configure this existing bundle” step, which may be intended but is broader than the simplest reading of the desired lifecycle.

- **Location:** `.github/workflows/perf-pr.yml` and `.github/workflows/perf-nightly.yml`
  - **Evidence:** Both workflows are configured and backed by locally verified examples, but their actual GitHub runner behavior cannot be fully exercised from the local sandbox.
  - **Likely cause / nature of issue:** Workflow structure and helper commands are implemented, but only a real GitHub Actions run will verify artifact retention, summary publishing, and timeout behavior exactly as intended.

- **Location:** Nightly benchmark signal
  - **Evidence:** The nightly bench profile completes locally, but some heavier matrix cells show more spread and Criterion may suggest slightly longer target times for the slowest cases.
  - **Likely cause / nature of issue:** The expanded nightly matrix is intentionally broader and noisier than the PR bench path, which is expected for scheduled performance exploration.

- **Location:** `perf-budgets.yaml` smoke `pack_build_smoke`, `bundle_build_smoke`, and `bundle_inspect_artifact_smoke`
  - **Evidence:** Local runs of the latest released `greentic-dev` and `greentic-bundle` showed very short wall times with high percentage swings across thread counts because the workloads are too small for stable scaling assertions.
  - **Likely cause / nature of issue:** The smoke pack-build, bundle-build, and artifact-inspect scenarios are useful as quick absolute-time guards, but they are too tiny to enforce strict thread-scaling regressions without flaking.

## 5. Notes for Future Work

- Exercise `perf-pr.yml` and `perf-nightly.yml` in GitHub Actions and tune artifact naming, retention, timeout policy, and command scopes based on real runner output from the latest released `gtc`.
- Report and track the released `gtc start` behavior that still launches cloudflared for the local-only runtime fixture even when setup disables public web hosting.
- Expand `perf-budgets.yaml` to medium and heavy generated fixtures once those scenarios are validated through real workflow runs.
- Tighten the current budget thresholds after the repo can run a real `gtc` binary consistently in both local and CI environments.
- Move scaling-sensitive assertions onto medium or heavy fixture scenarios once those runs are stable enough to provide meaningful multi-thread comparisons.
- Add a separate branch-local CLI workflow if the repo needs to compare unreleased `gtc` changes against the latest released baseline.
