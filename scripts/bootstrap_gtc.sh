#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

ensure_cargo_bin_on_path() {
  local cargo_home cargo_bin
  cargo_home="${CARGO_HOME:-$HOME/.cargo}"
  cargo_bin="$cargo_home/bin"

  case ":$PATH:" in
    *":$cargo_bin:"*) ;;
    *) export PATH="$cargo_bin:$PATH" ;;
  esac

  if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "$cargo_bin" >> "$GITHUB_PATH"
  fi
}

ensure_cargo_bin_on_path
need_cmd cargo

if ! command -v cargo-binstall >/dev/null 2>&1; then
  echo "Installing cargo-binstall..."
  cargo install cargo-binstall --locked
fi

echo "Installing latest released gtc with cargo binstall..."
cargo binstall gtc --no-confirm --force

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
