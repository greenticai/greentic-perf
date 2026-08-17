# Scripts

This directory holds helper scripts for fixture generation, latest-`gtc` bootstrap, result summarisation, and local developer workflows.

Current scripts:

- `lib/retry.sh`: shared `retry()` helper, sourced (not executed) by every script that reaches ghcr.io or crates.io. Re-attempts with jittered exponential backoff; tune with `BOOTSTRAP_RETRY_ATTEMPTS` (default `3`) and `BOOTSTRAP_RETRY_INITIAL_SECONDS` (default `5`). Jitter matters because the nightly matrix trips ghcr throttling in lockstep, and a throttled pull comes back as a misleading `401 Not authorized`.
- `bootstrap_gtc.sh`: installs the latest released `gtc` via `cargo-binstall` and refreshes installable artifacts with `gtc install`. Every network step goes through `retry()`.
- `tests/bootstrap_retry_test.sh`: regression tests for that `retry()` helper, plus a guard that fails if any shipped script calls `gtc install` / `cargo binstall` / `cargo install` outside `retry()`. Uses fake commands only -- no network, no cargo. Run by `ci/local_check.sh`.
- `generate_fixtures.sh`: renders deterministic source answers into real generated pack and bundle workspaces by driving `gtc wizard --answers ...`, then applies bundle setup via `gtc setup --no-ui --answers ...`, then packages `.gtbundle` artifacts.
- `generate_runtime_fixtures.sh`: creates the runtime startup bundle fixture with `gtc wizard --answers ...`, applies runtime setup with `gtc setup --no-ui --answers ...`, and packages the runtime `.gtbundle` artifact. Its cache-hit-path `gtc install` also goes through `retry()`. The remaining limitation is the released `gtc start` behavior for the local-only WebChat runtime, not the wizard/setup generation flow.
- `check_fixtures.sh`: runs the fixture generator and validates the expected outputs.
- `setup_webchat_perf.sh`: one-time setup/start for runtime webchat perf. Captures `wizard --schema`, applies `greentic-pack`/`greentic-bundle` wizard answers, runs `gtc setup --no-ui --answers`, starts runtime, and writes a reusable session file.
- `run_webchat_perf.sh`: run-only load phase. Reuses the setup session, performs warmup, and executes threaded throughput sweeps (`1..20` by default) with probe-first endpoint fallback.
- `runtime_webchat_perf.sh`: convenience wrapper that runs `setup_webchat_perf.sh` then `run_webchat_perf.sh`.

Keep scripts small, deterministic where possible, and safe to run in CI.
