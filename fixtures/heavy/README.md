# Heavy Fixture Tier

This tier is intentionally larger and more fan-out heavy than the smoke and medium fixtures. It is still deterministic and local-only, but it provides more filesystem surface area for future nightly and thread-scaling runs.

Contents:

- `workspace.json`: fixture metadata.
- `packs/heavy-pack/pack.json`: pack manifest referencing many local assets.
- `bundles/heavy-bundle.json`: bundle configuration covering multiple asset groups.
- `assets/regions/*.json`: several deterministic JSON files.
- `assets/content/*.txt`: several deterministic text fragments.

This tier is present now so future nightly and budget work can start from tracked fixture content instead of placeholder directories.
