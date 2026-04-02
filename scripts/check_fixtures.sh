#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
tiers=("$@")

if [ "${#tiers[@]}" -eq 0 ]; then
  tiers=(smoke medium heavy)
fi

missing_tiers=()
for tier in "${tiers[@]}"; do
  pack_file="$ROOT_DIR/fixtures-gen/$tier/packs/perf-$tier-pack/pack.yaml"
  bundle_file="$ROOT_DIR/fixtures-gen/$tier/bundles/perf-$tier-bundle/bundle.yaml"
  artifact_file="$ROOT_DIR/fixtures-gen/$tier/artifacts/perf-$tier-bundle.gtbundle"
  if [ ! -f "$pack_file" ] || [ ! -f "$bundle_file" ] || [ ! -f "$artifact_file" ]; then
    missing_tiers+=("$tier")
  fi
done

if [ "${#missing_tiers[@]}" -gt 0 ]; then
  "$ROOT_DIR/scripts/generate_fixtures.sh" "${missing_tiers[@]}"
else
  echo "Fixtures already present for tiers: ${tiers[*]}"
fi

for tier in "${tiers[@]}"; do
  test -f "$ROOT_DIR/fixtures-gen/$tier/packs/perf-$tier-pack/pack.yaml"
  test -f "$ROOT_DIR/fixtures-gen/$tier/bundles/perf-$tier-bundle/bundle.yaml"
  test -f "$ROOT_DIR/fixtures-gen/$tier/artifacts/perf-$tier-bundle.gtbundle"
done

echo "Fixture generation OK"
