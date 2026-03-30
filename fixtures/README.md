# Fixtures

Fixtures model end-to-end `gtc` workloads for performance and hang-detection runs.

This repo still contains the earlier tracked deterministic fixture tiers:

- `smoke/`: tiny, fast scenarios suitable for pull requests and local smoke checks.
- `medium/`: more representative multi-file scenarios that still stay CI-friendly.
- `heavy/`: larger fan-out scenarios intended to exercise concurrency and filesystem traversal more aggressively.

They remain useful as bootstrap reference content, but the active perf generator and workflow inputs now live under `fixtures-src/` and `fixtures-gen/`. Each tier README describes what the older tracked snapshot stresses.
