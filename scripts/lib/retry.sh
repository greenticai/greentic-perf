#!/usr/bin/env bash
# Shared retry helper for the perf scripts. Source it; do not execute it.
#
#   source "$ROOT_DIR/scripts/lib/retry.sh"
#   retry "gtc install" gtc install
#
# It lives here rather than inside bootstrap_gtc.sh because two scripts reach
# ghcr.io: bootstrap_gtc.sh (7 cargo binstall downloads plus a `gtc install`
# that pulls ~90 packs and components one at a time) and
# generate_runtime_fixtures.sh (a second `gtc install` on the cargo-bin cache
# hit path). Both need the same protection, and a copy in each would drift.

# Re-run a command while it keeps failing.
#
# Every call site is network-bound, and the nightly runs them across a job
# matrix that all starts at once -- roughly 1,500 anonymous ghcr.io requests
# within a few minutes, from one runner IP pool. ghcr answers a throttled pull
# with `401 Not authorized`, which reads like a permission problem but is
# transient, so a lone blip is expected rather than exceptional. One such blip
# used to fail the whole job.
#
# Retrying is safe because these commands resume rather than restart: binstall
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
