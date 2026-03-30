#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
tiers=("$@")

if [ "${#tiers[@]}" -eq 0 ]; then
  tiers=(smoke medium heavy)
fi

"$ROOT_DIR/scripts/generate_fixtures.sh" "${tiers[@]}"

for tier in "${tiers[@]}"; do
  test -f "$ROOT_DIR/fixtures-gen/$tier/packs/perf-$tier-pack/pack.yaml"
  test -f "$ROOT_DIR/fixtures-gen/$tier/bundles/perf-$tier-bundle/bundle.yaml"
  test -f "$ROOT_DIR/fixtures-gen/$tier/artifacts/perf-$tier-bundle.gtbundle"
done

echo "Fixture generation OK"
