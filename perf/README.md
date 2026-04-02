# Perf Harness

This directory contains the dedicated performance harness described in `.codex/PR-initial-creation.md`.

Current contents:

- `src/` with the reusable scenario runner and supporting types
- `tests/` with integration coverage for the runner
- `benches/` with Criterion benchmark entrypoints that execute CLI-style subprocess journeys

The runner currently executes a configured real CLI binary, copies fixtures into a temporary workspace, applies thread overrides, captures stdout/stderr tails, and serializes scenario results. The initial benchmark suite lives in `benches/cli_bench.rs` and resolves the binary under test from `GREENTIC_PERF_BIN`, `GTC_BIN`, or the named Greentic CLI on `PATH`.

Runtime-focused helpers also live under `examples/`, including `runtime_webchat_load.rs` for threaded Direct Line/WebChat ingress throughput measurements.
