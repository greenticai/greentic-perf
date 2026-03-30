#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need_cmd cargo

if ! command -v cargo-binstall >/dev/null 2>&1; then
  echo "Installing cargo-binstall..."
  cargo install cargo-binstall --locked
fi

echo "Installing latest released gtc with cargo binstall..."
cargo binstall gtc --no-confirm

need_cmd gtc

echo "gtc version:"
gtc --version || true

echo "Refreshing latest installable Greentic artifacts..."
if [ -n "${GREENTIC_TENANT:-}" ]; then
  gtc install --tenant "${GREENTIC_TENANT}"
else
  gtc install
fi

echo "Bootstrap complete."
