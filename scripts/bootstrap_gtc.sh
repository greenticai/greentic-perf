#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

# Re-run a command while it keeps failing.
#
# Every step in this script is network-bound: seven cargo binstall downloads
# followed by a `gtc install` that pulls ~40 packs from ghcr.io one at a time.
# A single dropped connection anywhere in that sequence fails the whole job,
# and the nightly runs this across a job matrix that all starts at once, so a
# lone transport blip is expected rather than exceptional.
#
# Retrying is safe because both commands resume rather than restart: binstall
# re-downloads only what it was installing, and `gtc install` skips artifacts
# already in its cache.
#
# Backoff doubles and carries jitter so matrix jobs that fail together do not
# retry in lockstep and collide again.
retry() {
  local description="$1"
  shift

  local attempts="${BOOTSTRAP_RETRY_ATTEMPTS:-3}"
  local delay="${BOOTSTRAP_RETRY_INITIAL_SECONDS:-5}"
  local attempt=1

  while true; do
    if "$@"; then
      return 0
    fi

    if [ "$attempt" -ge "$attempts" ]; then
      echo "$description failed after $attempts attempt(s); giving up" >&2
      return 1
    fi

    local sleep_for=$((delay + RANDOM % (delay + 1)))
    echo "$description failed (attempt $attempt/$attempts); retrying in ${sleep_for}s" >&2
    sleep "$sleep_for"

    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
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
  retry "cargo install cargo-binstall" cargo install cargo-binstall --locked
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
if [ -n "${GREENTIC_TENANT:-}" ]; then
  retry "gtc install" gtc install --tenant "${GREENTIC_TENANT}"
else
  retry "gtc install" gtc install
fi

echo "Bootstrap complete."
