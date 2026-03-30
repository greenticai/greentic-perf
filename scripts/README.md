# Scripts

This directory holds helper scripts for fixture generation, latest-`gtc` bootstrap, result summarisation, and local developer workflows.

Current scripts:

- `bootstrap_gtc.sh`: installs the latest released `gtc` via `cargo-binstall` and refreshes installable artifacts with `gtc install`.
- `generate_fixtures.sh`: renders deterministic source answers into real generated pack and bundle workspaces by driving `gtc wizard --answers ...`, then applies bundle setup via `gtc setup --answers ...`, then packages `.gtbundle` artifacts.
- `generate_runtime_fixtures.sh`: creates the runtime startup bundle fixture with `gtc wizard --answers ...`, applies runtime setup with `gtc setup --answers ...`, and packages the runtime `.gtbundle` artifact. The remaining limitation is the released `gtc start` behavior for the local-only WebChat runtime, not the wizard/setup generation flow.
- `check_fixtures.sh`: runs the fixture generator and validates the expected outputs.

Keep scripts small, deterministic where possible, and safe to run in CI.
