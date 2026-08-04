#!/usr/bin/env bash
# Regression tests for the retry() helper in scripts/bootstrap_gtc.sh.
#
# retry() guards every network step of the nightly bootstrap, so a regression
# here silently reintroduces the failure mode it exists to prevent: one dropped
# connection failing the whole job. These tests use fake commands only -- no
# network, no cargo, no gtc.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bootstrap="$script_dir/../bootstrap_gtc.sh"

if [ ! -f "$bootstrap" ]; then
  echo "FAIL: cannot find $bootstrap" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Extract retry() from the real script so these tests exercise the shipped
# code rather than a copy that can drift out of sync with it.
sed -n '/^retry() {/,/^}/p' "$bootstrap" > "$work/retry.sh"
# shellcheck disable=SC1090
source "$work/retry.sh"

if ! declare -F retry >/dev/null; then
  echo "FAIL: could not extract retry() from $bootstrap" >&2
  exit 1
fi

fails=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name (expected '$expected', got '$actual')" >&2
    fails=$((fails + 1))
  fi
}

counter="$work/counter"

# Fails its first "$1" invocations, then succeeds.
flaky() {
  local fail_until="$1" count
  count=$(<"$counter")
  count=$((count + 1))
  echo "$count" > "$counter"
  [ "$count" -gt "$fail_until" ]
}

always_fails() { echo 1 >> "$counter.always"; return 1; }
always_succeeds() { echo 1 >> "$counter.ok"; return 0; }

export BOOTSTRAP_RETRY_INITIAL_SECONDS=0
export BOOTSTRAP_RETRY_ATTEMPTS=3

echo 0 > "$counter"
retry "flaky" flaky 2 >/dev/null 2>&1
check "recovers from two transient failures" "0" "$?"
check "stops as soon as it succeeds" "3" "$(<"$counter")"

: > "$counter.always"
retry "always_fails" always_fails >/dev/null 2>&1
check "propagates failure once attempts are exhausted" "1" "$?"
check "runs exactly the configured number of attempts" "3" "$(wc -l < "$counter.always")"

: > "$counter.ok"
retry "always_succeeds" always_succeeds >/dev/null 2>&1
check "a passing command runs once" "1" "$(wc -l < "$counter.ok")"

: > "$counter.always"
BOOTSTRAP_RETRY_ATTEMPTS=1 retry "always_fails" always_fails >/dev/null 2>&1
check "attempts=1 disables retrying" "1" "$(wc -l < "$counter.always")"

# gtc install takes flags such as --tenant; argv must survive the indirection.
observed="$work/args"
record_args() { printf '%s\n' "$#" > "$observed"; printf '%s\n' "$@" >> "$observed"; }
retry "record_args" record_args "one two" three >/dev/null 2>&1
check "passes argv through without word splitting" "2" "$(head -1 "$observed")"
check "preserves an argument containing a space" "one two" "$(sed -n 2p "$observed")"

: > "$counter.always"
stdout="$(BOOTSTRAP_RETRY_ATTEMPTS=2 retry "always_fails" always_fails 2>/dev/null)"
check "retry chatter stays off stdout" "" "$stdout"

: > "$counter.always"
start=$SECONDS
BOOTSTRAP_RETRY_ATTEMPTS=2 BOOTSTRAP_RETRY_INITIAL_SECONDS=1 \
  retry "always_fails" always_fails >/dev/null 2>&1
elapsed=$((SECONDS - start))
if [ "$elapsed" -ge 1 ]; then
  echo "ok   - backs off between attempts (${elapsed}s)"
else
  echo "FAIL - did not back off between attempts (${elapsed}s)" >&2
  fails=$((fails + 1))
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "all retry() tests passed"
else
  echo "$fails retry() test(s) failed" >&2
  exit 1
fi
