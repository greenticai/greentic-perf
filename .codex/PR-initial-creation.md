PR-00 — Bootstrap greentic-perf

Title: init greentic-perf repository for end-to-end gtc performance testing

Goal

Create the standalone repo and its basic layout.

Add
greentic-perf/
  README.md
  Cargo.toml
  rust-toolchain.toml
  .gitignore
  .github/workflows/
  fixtures/
    smoke/
    medium/
    heavy/
  perf/
    benches/
    tests/
    src/
  scripts/
  docs/
Notes

This repo should be a runner + fixtures + policies repo. It should not become another implementation repo.

Acceptance criteria
Repo builds on Rust 1.91
cargo test passes
empty smoke workflow runs successfully
PR-01 — Add the scenario runner

Title: add subprocess scenario runner for real gtc end-to-end execution

Goal

Create a reusable Rust harness that runs the real gtc binary as a child process, captures timing, exit status, stdout/stderr tails, and supports thread-count overrides.

Add
perf/src/scenario.rs
perf/src/result.rs
perf/src/threads.rs
perf/src/temp_workspace.rs
Core API
run_scenario(
    scenario_name: &str,
    repo_ref: RepoRef,
    args: &[&str],
    fixture: &Path,
    threads: usize,
    timeout: Duration,
) -> ScenarioResult
Why this PR first

Everything else depends on one stable execution layer.

Acceptance criteria
Can run gtc --help
Can run at least one real command against a fixture
Produces machine-readable result JSON
PR-02 — Add smoke end-to-end tests with timeout protection

Title: add timeout-guarded smoke e2e tests for gtc

Goal

Catch basic hangs early.

Add
perf/tests/smoke_cli.rs
perf/tests/smoke_threads.rs
.config/nextest.toml

cargo-nextest supports slow-test reporting, per-test termination after repeated timeout periods, and a global timeout for the run, which makes it a good fit for “detect hangs, don’t let CI stall forever.”

Initial scenarios
gtc --help
gtc version or equivalent
one small doctor/validate/build scenario
same scenario with 1, 4, 8 threads
Acceptance criteria
a stuck scenario is terminated by nextest config
CI fails clearly on timeout
stderr/stdout tail is uploaded as artifact
PR-03 — Add Criterion benchmark suite for real CLI journeys

Title: add criterion benchmarks for gtc end-to-end scenario timings

Goal

Measure regressions, not just hangs.

Add
perf/benches/cli_bench.rs
benchmark groups by scenario and thread count
benchmark IDs like:
pack_doctor/smoke/t1
pack_doctor/smoke/t4
bundle_build/medium/t8

Criterion is designed for statistics-driven benchmarking and supports stored baselines plus comparison against named baselines, which is exactly what you want for regression tracking over time.

Important design choice

Benchmarks should execute real gtc subprocesses, not internal functions.

Acceptance criteria
cargo bench --bench cli_bench works locally
saved baseline support is documented
benchmark output lands in target/criterion/
PR-04 — Add fixture packs/bundles for realistic end-to-end flows

Title: add representative fixtures for smoke medium and heavy gtc workflows

Goal

Stop benchmarking toy commands only.

Add fixtures
fixtures/smoke/ — tiny pack/flow/component
fixtures/medium/ — more realistic multi-asset example
fixtures/heavy/ — intentionally concurrency-sensitive scenario with more files and fan-out
Fixture principles
deterministic
no external network dependency by default
small enough for PR CI, heavier variants for nightly
clear README per fixture describing what it stresses
Acceptance criteria
each fixture maps to at least one benchmark and one timeout test
fixtures are reproducible from clean checkout
PR-05 — Add performance budgets and scaling assertions

Title: add scenario budgets and thread-scaling regression checks

Goal

Turn measurements into policy.

Add
perf-budgets.yaml
validator/test that reads budgets
assertions for:
max wall time
successful exit
non-regression thresholds
“more threads must not get much worse”
Example
scenarios:
  - name: pack_doctor_smoke
    args: ["pack", "doctor"]
    fixture: fixtures/smoke
    budgets:
      "1": { max_ms: 3000 }
      "4": { max_ms: 2200 }
      "8": { max_ms: 2500 }
    scaling:
      max_regression_vs_t1_pct: 15
      max_regression_vs_prev_pct: 20
Acceptance criteria
budget failures are explicit and readable
bad scaling fails even when the command still succeeds
PR-06 — Add GitHub Actions PR workflow

Title: add pull-request workflow for smoke perf and hang detection

Goal

Fast signal on every PR.

Add workflow

.github/workflows/perf-pr.yml

What it should do
install Rust
build gtc
run smoke nextest suite
run a small perf matrix only
upload result JSON, logs, and benchmark output as artifacts

GitHub Actions workflows can run on repository events and store artifacts from workflow runs; artifact upload is supported through the upload-artifact action.

Keep PR workflow small

Only:

smoke fixture
maybe medium fixture for one key scenario
threads 1 and 4
Acceptance criteria
runs in reasonable PR time
produces artifacts on success and failure
does not require nightly-sized fixtures
PR-07 — Add scheduled nightly workflow

Title: add nightly full e2e benchmark workflow with saved baselines

Goal

Run the expensive matrix outside PRs.

Add workflow

.github/workflows/perf-nightly.yml

What it should do
run on schedule and manual dispatch
execute heavier scenarios
run thread matrix 1/2/4/8/16
save benchmark artifacts
publish simple markdown summary to workflow output

GitHub Actions supports scheduled and manually triggered workflows through workflow syntax and event triggers.

Acceptance criteria
nightly run completes without blocking normal PR velocity
benchmark outputs and logs are retained as artifacts
summary shows fastest/slowest scenarios and regressions
PR-08 — Add diagnostics for “where did it hang?”

Title: add phase timing diagnostics and last-known-progress markers

Goal

When a run gets slow or stuck, make the failure actionable.

Add
phase markers in the runner:
checkout/setup
fixture prep
command start
command end
optional structured log format:
{"phase":"fixture_prep","elapsed_ms":182}
{"phase":"command_run","elapsed_ms":4123}
Acceptance criteria
timeout failures tell you the last completed phase
logs are easy to inspect from artifacts
PR-09 — Add documentation and contribution contract

Title: document greentic-perf scope governance and scenario contribution rules

Goal

Keep the repo clean over time.

Document
what belongs here
what does not belong here
how to add a fixture
how to add a scenario
how to set/update budgets
how to interpret regressions
how PR smoke differs from nightly full runs
Key rule

greentic-perf owns:

end-to-end gtc performance
real CLI subprocess scenarios
hang detection
thread-scaling checks
cross-fixture regression history

It should not become a dumping ground for crate-local microbenchmarks.

Suggested order of merge
Phase 1: make it real
PR-00 bootstrap
PR-01 scenario runner
PR-02 timeout smoke tests
Phase 2: make it measurable
PR-03 Criterion benchmarks
PR-04 realistic fixtures
PR-05 budgets and scaling assertions
Phase 3: make it operational
PR-06 PR workflow
PR-07 nightly workflow
PR-08 diagnostics
PR-09 docs/governance