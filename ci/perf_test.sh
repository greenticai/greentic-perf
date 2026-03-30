#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/perf-local"
RESULTS_DIR="$ARTIFACT_DIR/results"
LOGS_DIR="$ARTIFACT_DIR/logs"
SUMMARY_PATH="$ARTIFACT_DIR/summary.md"

step() {
  printf '\n==> %s\n' "$1"
}

run_scenario() {
  scenario_name="$1"
  binary="$2"
  fixture="$3"
  threads="$4"
  timeout_ms="$5"
  shift 5

  step "scenario $scenario_name"
  GREENTIC_PERF_BIN="$binary" cargo run -p greentic-perf-harness --example scenario_json -- \
    "$scenario_name" \
    "$fixture" \
    "$threads" \
    "$timeout_ms" \
    "$@" \
    > "$RESULTS_DIR/$scenario_name.json" \
    2> "$LOGS_DIR/$scenario_name.log"
}

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

step "bootstrap latest released gtc"
bash "$ROOT_DIR/scripts/bootstrap_gtc.sh"

step "generate smoke/medium/heavy fixtures"
bash "$ROOT_DIR/scripts/generate_fixtures.sh" smoke medium heavy

step "generate runtime fixture"
bash "$ROOT_DIR/scripts/generate_runtime_fixtures.sh"

step "validate perf budgets"
cargo test -p greentic-perf-harness --test perf_budgets -- --nocapture

step "validate runtime startup"
cargo test -p greentic-perf-harness --test runtime_startup -- --nocapture

run_scenario "smoke-pack-build-t1" "greentic-dev" "fixtures-gen/smoke/packs/perf-smoke-pack" "1" "5000" pack build --in .
run_scenario "smoke-pack-build-t2" "greentic-dev" "fixtures-gen/smoke/packs/perf-smoke-pack" "2" "5000" pack build --in .
run_scenario "smoke-pack-build-t4" "greentic-dev" "fixtures-gen/smoke/packs/perf-smoke-pack" "4" "5000" pack build --in .
run_scenario "smoke-pack-build-t8" "greentic-dev" "fixtures-gen/smoke/packs/perf-smoke-pack" "8" "5000" pack build --in .
run_scenario "smoke-pack-build-t16" "greentic-dev" "fixtures-gen/smoke/packs/perf-smoke-pack" "16" "5000" pack build --in .

run_scenario "medium-bundle-build-t1" "greentic-bundle" "fixtures-gen/medium/bundles/perf-medium-bundle" "1" "5000" build
run_scenario "medium-bundle-build-t2" "greentic-bundle" "fixtures-gen/medium/bundles/perf-medium-bundle" "2" "5000" build
run_scenario "medium-bundle-build-t4" "greentic-bundle" "fixtures-gen/medium/bundles/perf-medium-bundle" "4" "5000" build
run_scenario "medium-bundle-build-t8" "greentic-bundle" "fixtures-gen/medium/bundles/perf-medium-bundle" "8" "5000" build
run_scenario "medium-bundle-build-t16" "greentic-bundle" "fixtures-gen/medium/bundles/perf-medium-bundle" "16" "5000" build

run_scenario "heavy-bundle-build-t1" "greentic-bundle" "fixtures-gen/heavy/bundles/perf-heavy-bundle" "1" "5000" build
run_scenario "heavy-bundle-build-t2" "greentic-bundle" "fixtures-gen/heavy/bundles/perf-heavy-bundle" "2" "5000" build
run_scenario "heavy-bundle-build-t4" "greentic-bundle" "fixtures-gen/heavy/bundles/perf-heavy-bundle" "4" "5000" build
run_scenario "heavy-bundle-build-t8" "greentic-bundle" "fixtures-gen/heavy/bundles/perf-heavy-bundle" "8" "5000" build
run_scenario "heavy-bundle-build-t16" "greentic-bundle" "fixtures-gen/heavy/bundles/perf-heavy-bundle" "16" "5000" build

run_scenario "smoke-bundle-artifact-inspect-t1" "greentic-bundle" "fixtures-gen/smoke" "1" "5000" inspect --artifact artifacts/perf-smoke-bundle.gtbundle --json --offline
run_scenario "smoke-bundle-artifact-inspect-t4" "greentic-bundle" "fixtures-gen/smoke" "4" "5000" inspect --artifact artifacts/perf-smoke-bundle.gtbundle --json --offline

step "run nightly benchmark profile"
GREENTIC_BENCH_PROFILE=nightly cargo bench -p greentic-perf-harness --bench cli_bench -- --save-baseline local-nightly --noplot

step "build local markdown summary"
cargo run -p greentic-perf-harness --example criterion_summary -- target/criterion "$SUMMARY_PATH"

step "done"
printf 'Scenario JSON: %s\n' "$RESULTS_DIR"
printf 'Scenario logs: %s\n' "$LOGS_DIR"
printf 'Bench summary: %s\n' "$SUMMARY_PATH"
