# Medium Fixture Tier

This tier models a somewhat richer multi-asset workspace than the smoke tier while remaining cheap enough for CI-oriented runs.

Contents:

- `workspace.json`: fixture metadata.
- `packs/catalog/pack.json`: a pack manifest with multiple assets.
- `bundles/catalog-bundle.json`: a bundle using more than one input.
- `assets/`: deterministic text and JSON content.

The medium fixture is intended to become the first step beyond pure smoke validation in later workflows.
