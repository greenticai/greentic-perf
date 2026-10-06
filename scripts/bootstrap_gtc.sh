#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/lib/retry.sh
source "$ROOT_DIR/scripts/lib/retry.sh"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

install_bin() {
  local package="$1"
  echo "Installing latest released $package with cargo binstall..."
  retry "cargo binstall $package" \
    cargo binstall "$package" --no-confirm --force --locked
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
  # Bootstrap from the prebuilt release binary: nothing is compiled, so a
  # cargo-binstall dependency raising its MSRV above the pinned toolchain
  # cannot break this step (cargo-binstall 1.22.0 did exactly that).
  binstall_ok=0
  for attempt in 1 2 3; do
    # `curl | bash` would hide a download failure: the pipeline reports
    # bash's status, and bash succeeds on empty input. Download, then run.
    binstall_installer="$(mktemp)"
    if curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh -o "$binstall_installer" && bash "$binstall_installer"; then
      hash -r
      if command -v cargo-binstall >/dev/null 2>&1; then binstall_ok=1; fi
    fi
    rm -f "$binstall_installer"
    if [ "$binstall_ok" -eq 1 ]; then break; fi
    sleep $((attempt * 5))
  done
  if [ "$binstall_ok" -ne 1 ]; then
    # Last release whose bundled lockfile still builds on 1.95.0.
    cargo install cargo-binstall --locked --version 1.21.1
  fi
fi

GTC_RELEASE="${GTC_RELEASE:-1.1.7}"

for package in \
  "gtc@>=${GTC_RELEASE}" \
  greentic-dev \
  greentic-pack \
  greentic-bundle \
  greentic-setup \
  greentic-operator \
  greentic-deployer
do
  install_bin "$package"
done

need_cmd gtc
need_cmd greentic-dev
need_cmd greentic-pack
need_cmd greentic-bundle
need_cmd greentic-setup

echo "gtc version:"
gtc --version || true

echo "Refreshing latest installable Greentic artifacts..."
# `--install-binaries-only` skips `gtc install`'s second phase: an
# all-or-nothing prefetch of every pack and component in the release. One
# transient ghcr.io blob error anywhere in that loop aborts the whole install,
# and the skip-list is keyed off a release index written only after the loop
# fully succeeds — so the retry redoes every pull instead of resuming. That is
# why a failure shows three attempts against three DIFFERENT packs, e.g. run
# 33610893351: component-adapter-pack, then weatherapi-pack, then
# router-lite-pack. It cost 3 of the last 12 Perf PR runs.
#
# Nothing here reads that prefetch. The scenarios drive locally generated
# fixtures (fixtures-gen/smoke/packs/perf-smoke-pack), and the one OCI pack
# this repo uses is named by explicit `oci://ghcr.io/...:latest` reference in
# generate_runtime_fixtures.sh / setup_webchat_perf.sh, so it is pulled on
# demand at wizard time either way; the release index only maps the `:stable`
# channel tag, which no fixture here uses.
#
# The toolchain release context that `gtc start` needs is still installed:
# that is the binaries phase, which this flag keeps.
if [ -n "${GREENTIC_TENANT:-}" ]; then
  retry "gtc install" gtc install --install-binaries-only --tenant "${GREENTIC_TENANT}"
else
  retry "gtc install" gtc install --install-binaries-only
fi

echo "Bootstrap complete."
