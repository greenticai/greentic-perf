# greentic-perf Contribution Contract

## Purpose

`greentic-perf` exists to measure and guard the performance characteristics of real `gtc` command journeys. It is a runner + fixtures + policies repository. It should help us answer questions such as:

- Does a representative CLI journey still complete successfully?
- Did wall time regress for an important scenario?
- Did higher thread counts become unexpectedly worse?
- If a run hangs or slows down, what phase did it reach before that happened?

This repository is not intended to become another implementation repo for core Greentic product logic.

## What Belongs Here

This repository should own:

- scenario-runner code that executes real or representative `gtc` subprocesses
- deterministic fixture content for smoke, medium, and heavy performance tiers
- smoke tests, budget checks, and benchmark suites for performance validation
- CI workflows, artifact generation, and summary/reporting code for those checks
- documentation that explains how performance scenarios are added, validated, and interpreted

## What Does Not Belong Here

This repository should not become the primary home for:

- production `gtc` feature implementation
- shared business/domain models better owned by other Greentic repos
- network-dependent integration flows by default
- flaky benchmarks that cannot run deterministically from a clean checkout
- one-off local debugging scripts that are not safe or useful in shared workflows

If a type, interface, or behavior belongs in another Greentic crate, reuse it there rather than recreating it here.

## How To Add a Fixture

Use the existing fixture tiers intentionally:

- `fixtures-src/smoke/`: the smallest deterministic generated scenarios suitable for pull requests
- `fixtures-src/medium/`: richer but still CI-friendly multi-file scenarios
- `fixtures-src/heavy/`: larger fan-out scenarios intended for nightly or manual validation

When adding a fixture:

1. Choose the smallest tier that still represents the behavior you need to validate.
2. Keep the checked-in source answers deterministic and local-only by default.
3. Regenerate `fixtures-gen/` and confirm the produced pack workspace, bundle workspace, and `.gtbundle` artifact are valid.
4. Update `docs/fixtures.md` or `README.md` if the fixture model changes materially.
5. Make sure the generated fixture can be copied into a temp workspace without hidden external dependencies.

Good fixture changes are reproducible from a clean checkout and small enough for the intended workflow tier.

## How To Add a Scenario

All scenarios should flow through the shared runner in `perf/src/scenario.rs`.

When adding a new scenario:

1. Decide whether it belongs in smoke validation, budget policy, benchmarks, nightly-only coverage, or some combination.
2. Reuse `run_scenario(...)` instead of embedding bespoke subprocess logic in tests or benches.
3. Give the scenario a stable, descriptive name because that name shows up in JSON artifacts, benchmark IDs, and summaries.
4. Choose the fixture tier that matches the intended runtime and breadth.
5. If the scenario is expected to be long-running or more variable, prefer adding it to nightly workflows before PR-critical workflows.
6. Prefer generated pack and bundle workspaces from `fixtures-gen/` over hand-maintained ad-hoc payloads.

Prefer scenarios that are small, explicit, and easy to reason about. If a scenario needs custom behavior, document why it cannot reuse an existing flow.

## How To Set or Update Budgets

Budget policy lives in `perf-budgets.yaml`.

When changing budgets:

1. Start from measured results, not guesses.
2. Set `max_ms` to something that catches real regressions without making CI noisy.
3. Keep the `t1` baseline present for any scenario with scaling assertions.
4. Use `max_regression_vs_t1_pct` to cap how much worse higher-thread runs may be than the single-thread baseline.
5. Use `max_regression_vs_prev_pct` to catch sharp step regressions between adjacent thread counts.

If you need to loosen a budget, explain whether the cause is expected workload growth, toolchain variance, fixture growth, or a known limitation in the current fake-binary path.

## How To Interpret Regressions

Not every slower run means the product regressed in the same way.

Use this order of operations:

1. Check whether the scenario still succeeded.
2. Check whether it timed out and what `last_completed_phase` was.
3. Compare the result with the budget file and benchmark summaries.
4. Look at the fixture tier involved.
5. Decide whether the regression is isolated to one thread count, one fixture tier, or the entire matrix.

Common patterns:

- A timeout with `last_completed_phase = "fixture_prep"` usually points to workspace-copy or fixture-shape issues.
- A timeout with `last_completed_phase = "command_start"` usually means the child process was launched but did not finish.
- A regression at one higher thread count but not others can indicate scaling issues rather than general slowdown.
- Broader nightly-only noise may be acceptable where PR smoke must stay tight and deterministic.

## PR Smoke vs Nightly Full Runs

The repository intentionally separates fast signal from broad exploration.

PR smoke is for:

- fast hang detection
- small fixture coverage
- a narrow thread matrix
- artifacts that help explain failures on pull requests

Nightly runs are for:

- broader fixture coverage including medium and heavy tiers
- wider thread matrices such as `1/2/4/8/16`
- benchmark summaries and retained artifacts
- catching longer-tail regressions without blocking normal PR velocity

If a scenario is too slow, too noisy, or too broad for PRs, move it to nightly rather than weakening the entire PR signal.

## Repository Cleanliness Rules

To keep the repo maintainable over time:

- prefer reusing existing runner helpers instead of adding parallel execution paths
- keep fixture answers deterministic and the generated outputs minimal for their tier
- avoid duplicating benchmark logic between PR and nightly workflows
- keep workflow artifacts structured and machine-readable where practical
- update `.codex/repo_overview.md` whenever meaningful behavior changes
- run `bash ci/local_check.sh` before considering the work done

The repository stays healthy when code, fixtures, budgets, workflows, and docs evolve together rather than drifting apart.
