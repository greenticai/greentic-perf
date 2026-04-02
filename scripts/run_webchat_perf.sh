#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="${RUNTIME_PERF_ARTIFACTS_DIR:-$ROOT_DIR/artifacts/runtime-webchat-perf}"
RESULTS_DIR="$ARTIFACTS_DIR/results"
SUMMARY_MD="$ARTIFACTS_DIR/summary.md"
LOG_DIR="$ARTIFACTS_DIR/logs"
SESSION_FILE="$ARTIFACTS_DIR/session.json"

THREAD_START="${RUNTIME_PERF_THREAD_START:-1}"
THREAD_END="${RUNTIME_PERF_THREAD_END:-20}"
MESSAGES_PER_THREAD="${RUNTIME_PERF_MESSAGES_PER_THREAD:-10}"
REPEATS="${RUNTIME_PERF_REPEATS:-3}"
WARMUP_THREADS="${RUNTIME_PERF_WARMUP_THREADS:-2}"
WARMUP_MESSAGES="${RUNTIME_PERF_WARMUP_MESSAGES:-5}"
POLL_TIMEOUT_MS="${RUNTIME_PERF_POLL_TIMEOUT_MS:-12000}"
CLIENT_TIMEOUT_MS="${RUNTIME_PERF_CLIENT_TIMEOUT_MS:-12000}"
ACCEPT_INVALID_CERTS="${RUNTIME_PERF_ACCEPT_INVALID_CERTS:-1}"
PROBE_FIRST="${RUNTIME_PERF_PROBE_FIRST:-1}"
INGRESS_BASE_URL="${RUNTIME_PERF_INGRESS_BASE_URL:-}"
READINESS_TIMEOUT_SEC="${RUNTIME_PERF_READINESS_TIMEOUT_SEC:-60}"

RUNTIME_PID=""
EFFECTIVE_TENANT=""
EFFECTIVE_TEAM=""
BUNDLE_DIR=""
ENDPOINTS_PATH=""
BASE_URL_CANDIDATES=()

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

step() {
  printf "\n==> %s\n" "$1"
}

add_base_url_candidate() {
  local candidate="$1"
  if [ -z "$candidate" ]; then
    return 0
  fi
  local existing
  for existing in "${BASE_URL_CANDIDATES[@]:-}"; do
    if [ "$existing" = "$candidate" ]; then
      return 0
    fi
  done
  BASE_URL_CANDIDATES+=("$candidate")
}

origin_from_url() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit

value = sys.argv[1]
parts = urlsplit(value)
if not parts.scheme or not parts.netloc:
    raise SystemExit(0)
print(f"{parts.scheme}://{parts.netloc}")
PY
}

load_session() {
  if [ ! -f "$SESSION_FILE" ]; then
    echo "missing session file: $SESSION_FILE (run scripts/setup_webchat_perf.sh first)" >&2
    exit 1
  fi

  RUNTIME_PID="$(jq -r '.runtime_pid' "$SESSION_FILE")"
  BUNDLE_DIR="$(jq -r '.bundle_dir' "$SESSION_FILE")"
  ENDPOINTS_PATH="$(jq -r '.endpoints_path' "$SESSION_FILE")"
  EFFECTIVE_TENANT="$(jq -r '.tenant' "$SESSION_FILE")"
  EFFECTIVE_TEAM="$(jq -r '.team' "$SESSION_FILE")"
}

is_runtime_reachable() {
  if [ ! -f "$ENDPOINTS_PATH" ]; then
    return 1
  fi

  local gateway_host gateway_port
  gateway_host="$(jq -r '.gateway_listen_addr // empty' "$ENDPOINTS_PATH")"
  gateway_port="$(jq -r '.gateway_port // empty' "$ENDPOINTS_PATH")"
  if [ -z "$gateway_host" ] || [ -z "$gateway_port" ]; then
    return 1
  fi

  python3 - "$gateway_host" "$gateway_port" <<'PY' >/dev/null 2>&1
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(1.0)
try:
    s.connect((host, port))
    sys.exit(0)
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
}

latest_endpoints_path() {
  find "$BUNDLE_DIR/state/runtime" -type f -path '*/endpoints.json' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-
}

start_runtime_from_session() {
  local runtime_stdout runtime_stderr
  runtime_stdout="$(jq -r '.runtime_stdout' "$SESSION_FILE")"
  runtime_stderr="$(jq -r '.runtime_stderr' "$SESSION_FILE")"

  local used_fallback=0
  local deadline=$((SECONDS + READINESS_TIMEOUT_SEC))

  step "start runtime from saved session"
  gtc start "$BUNDLE_DIR" >"$runtime_stdout" 2>"$runtime_stderr" &
  RUNTIME_PID="$!"
  echo "runtime pid: $RUNTIME_PID"

  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! kill -0 "$RUNTIME_PID" >/dev/null 2>&1; then
      if [ "$used_fallback" -eq 0 ] && grep -q "unexpected argument '--admin-port'" "$runtime_stderr"; then
        echo "gtc start hit known --admin-port mismatch; retrying with greentic-start fallback"
        greentic-start start --bundle "$BUNDLE_DIR" --nats off --cloudflared off --ngrok off >"$runtime_stdout" 2>"$runtime_stderr" &
        RUNTIME_PID="$!"
        used_fallback=1
        sleep 1
        continue
      fi
      echo "runtime exited before readiness; see $runtime_stderr" >&2
      return 1
    fi

    local discovered_endpoints
    discovered_endpoints="$(latest_endpoints_path || true)"
    if [ -n "$discovered_endpoints" ]; then
      ENDPOINTS_PATH="$discovered_endpoints"
    fi

    if is_runtime_reachable; then
      jq \
        --argjson runtime_pid "$RUNTIME_PID" \
        --arg endpoints_path "$ENDPOINTS_PATH" \
        '.runtime_pid = $runtime_pid | .endpoints_path = $endpoints_path' \
        "$SESSION_FILE" > "$SESSION_FILE.tmp"
      mv "$SESSION_FILE.tmp" "$SESSION_FILE"
      return 0
    fi

    sleep 1
  done

  echo "runtime did not become ready within ${READINESS_TIMEOUT_SEC}s" >&2
  return 1
}

ensure_runtime_ready() {
  local discovered_endpoints
  discovered_endpoints="$(latest_endpoints_path || true)"
  if [ -n "$discovered_endpoints" ]; then
    ENDPOINTS_PATH="$discovered_endpoints"
  fi

  if [ "${RUNTIME_PID:-0}" -gt 0 ] && kill -0 "$RUNTIME_PID" >/dev/null 2>&1 && is_runtime_reachable; then
    return 0
  fi

  if is_runtime_reachable; then
    if runtime_token_probe_ok; then
      echo "runtime reachable even though recorded pid is not active; continuing"
      return 0
    fi
    echo "runtime port reachable but directline token probe failed; starting runtime from session"
    start_runtime_from_session
    return 0
  fi

  start_runtime_from_session
}

runtime_token_probe_ok() {
  if [ ! -f "$SESSION_FILE" ] || [ ! -f "$ENDPOINTS_PATH" ]; then
    return 1
  fi

  local session_ingress configured_ingress discovered_gateway discovered_public
  session_ingress="$(jq -r '.ingress_base_url // empty' "$SESSION_FILE")"
  configured_ingress="${INGRESS_BASE_URL:-$session_ingress}"
  discovered_gateway="$(jq -r '"http://" + .gateway_listen_addr + ":" + (.gateway_port|tostring)' "$ENDPOINTS_PATH" 2>/dev/null || true)"
  discovered_public="$(jq -r '.public_base_url // empty' "$ENDPOINTS_PATH" 2>/dev/null || true)"

  local candidates=()
  [ -n "$discovered_public" ] && candidates+=("$discovered_public")
  [ -n "$discovered_gateway" ] && candidates+=("$discovered_gateway")
  local ingress_origin
  ingress_origin="$(origin_from_url "$configured_ingress" || true)"
  [ -n "$ingress_origin" ] && candidates+=("$ingress_origin")
  [ -n "$configured_ingress" ] && candidates+=("$configured_ingress")

  local base_url
  for base_url in "${candidates[@]}"; do
    if probe_base_url "$base_url" "$EFFECTIVE_TENANT"; then
      return 0
    fi
  done
  return 1
}

configure_runtime_targets() {
  local session_ingress
  session_ingress="$(jq -r '.ingress_base_url // empty' "$SESSION_FILE")"
  local configured_ingress="${INGRESS_BASE_URL:-$session_ingress}"

  local discovered_gateway discovered_public
  discovered_gateway="$(jq -r '"http://" + .gateway_listen_addr + ":" + (.gateway_port|tostring)' "$ENDPOINTS_PATH")"
  discovered_public="$(jq -r '.public_base_url // empty' "$ENDPOINTS_PATH")"

  add_base_url_candidate "$discovered_public"
  add_base_url_candidate "$discovered_gateway"
  add_base_url_candidate "$(origin_from_url "$configured_ingress")"
  add_base_url_candidate "$configured_ingress"

  if [ "$PROBE_FIRST" = "1" ]; then
    prioritize_candidates_by_probe
  fi

  echo "effective tenant: $EFFECTIVE_TENANT"
  echo "base URL candidates (ordered):"
  local url
  for url in "${BASE_URL_CANDIDATES[@]}"; do
    echo "  - $url"
  done
}

probe_base_url() {
  local base_url="$1"
  local tenant="$2"

  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  local curl_opts=(-sS --max-time 5 -X POST)
  if [ "$ACCEPT_INVALID_CERTS" = "1" ]; then
    curl_opts+=(-k)
  fi

  local probe_urls=(
    "$base_url/v3/directline/tokens/generate"
    "$base_url/$tenant/v3/directline/tokens/generate"
    "$base_url/v1/messaging/webchat/$tenant/token"
  )

  local probe_url response status body
  for probe_url in "${probe_urls[@]}"; do
    response="$(curl "${curl_opts[@]}" -w $'\n%{http_code}' "$probe_url" 2>/dev/null || true)"
    status="$(tail -n1 <<<"$response")"
    body="$(sed '$d' <<<"$response")"

    if [[ "$status" =~ ^2[0-9][0-9]$ ]] && jq -e '.token | type=="string" and length>0' >/dev/null 2>&1 <<<"$body"; then
      return 0
    fi
  done

  return 1
}

prioritize_candidates_by_probe() {
  local preferred=()
  local fallback=()
  local base_url

  for base_url in "${BASE_URL_CANDIDATES[@]}"; do
    if probe_base_url "$base_url" "$EFFECTIVE_TENANT"; then
      preferred+=("$base_url")
    else
      fallback+=("$base_url")
    fi
  done

  if [ "${#preferred[@]}" -gt 0 ]; then
    BASE_URL_CANDIDATES=("${preferred[@]}" "${fallback[@]}")
    echo "probe-first mode: prioritized candidates with valid token responses"
  else
    echo "probe-first mode: no candidate returned a valid token response; keeping original order"
  fi
}

run_load_once() {
  local label="$1"
  local threads="$2"
  local messages="$3"
  local output_path="$4"
  local tls_flag=()

  if [ "$ACCEPT_INVALID_CERTS" = "1" ]; then
    tls_flag+=(--accept-invalid-certs)
  fi

  local attempt_log="$LOG_DIR/load-${label}.attempts.log"
  : > "$attempt_log"

  local base_url
  for base_url in "${BASE_URL_CANDIDATES[@]}"; do
    local tmp_out="$RESULTS_DIR/.${label}.tmp.json"
    local tmp_err="$RESULTS_DIR/.${label}.tmp.stderr.log"

    if cargo run -q -p greentic-perf-harness --example runtime_webchat_load -- \
      --label "$label" \
      --base-url "$base_url" \
      --tenant "$EFFECTIVE_TENANT" \
      --threads "$threads" \
      --messages-per-thread "$messages" \
      --poll-timeout-ms "$POLL_TIMEOUT_MS" \
      --client-timeout-ms "$CLIENT_TIMEOUT_MS" \
      "${tls_flag[@]}" \
      >"$tmp_out" 2>"$tmp_err"; then
      jq --arg base_url "$base_url" '. + {base_url_used: $base_url}' "$tmp_out" > "$output_path"
      rm -f "$tmp_out" "$tmp_err"
      return 0
    fi

    {
      echo "base_url=$base_url"
      cat "$tmp_err"
      echo
    } >> "$attempt_log"
    rm -f "$tmp_out" "$tmp_err"
  done

  echo "all base URL candidates failed for $label; see $attempt_log" >&2
  return 1
}

run_benchmark() {
  step "warm up runtime"
  run_load_once "warmup" "$WARMUP_THREADS" "$WARMUP_MESSAGES" "$RESULTS_DIR/warmup.json"

  step "run throughput sweep ${THREAD_START}..${THREAD_END} threads (${REPEATS} repeat(s) each)"
  : > "$RESULTS_DIR/results.runs.jsonl"
  : > "$RESULTS_DIR/results.jsonl"
  local t
  for t in $(seq "$THREAD_START" "$THREAD_END"); do
    rm -f "$RESULTS_DIR/t${t}.r"*.json
    local r
    for r in $(seq 1 "$REPEATS"); do
      local result_path="$RESULTS_DIR/t${t}.r${r}.json"
      run_load_once "t${t}.r${r}" "$t" "$MESSAGES_PER_THREAD" "$result_path"
      jq -c . "$result_path" >> "$RESULTS_DIR/results.runs.jsonl"
    done
    python3 - "$t" "$RESULTS_DIR" > "$RESULTS_DIR/t${t}.json" <<'PY'
import glob
import json
import math
import statistics
import sys
from pathlib import Path

thread = int(sys.argv[1])
results_dir = Path(sys.argv[2])
paths = sorted(glob.glob(str(results_dir / f"t{thread}.r*.json")))
if not paths:
    raise SystemExit(f"no run results found for thread={thread}")

runs = [json.loads(Path(p).read_text()) for p in paths]

def percentile(sorted_values, p):
    if not sorted_values:
        return 0.0
    idx = max(0, min(len(sorted_values) - 1, math.ceil((p / 100.0) * len(sorted_values)) - 1))
    return float(sorted_values[idx])

throughput = sorted(float(r["throughput_msgs_per_sec"]) for r in runs)
elapsed = sorted(float(r["elapsed_ms"]) for r in runs)
ok = sorted(int(r["successful_requests"]) for r in runs)
fail = sorted(int(r["failed_requests"]) for r in runs)
bases = [r.get("base_url_used", "n/a") for r in runs]
first = runs[0]

out = {
    "label": f"t{thread}",
    "threads": thread,
    "repeats": len(runs),
    "tenant": first.get("tenant"),
    "messages_per_thread": int(first.get("messages_per_thread", 0)),
    "total_requests_per_run": int(first.get("total_requests", 0)),
    "successful_requests_median": int(statistics.median(ok)),
    "failed_requests_median": int(statistics.median(fail)),
    "elapsed_ms_median": int(round(statistics.median(elapsed))),
    "throughput_msgs_per_sec_median": statistics.median(throughput),
    "throughput_msgs_per_sec_p95": percentile(throughput, 95),
    "throughput_msgs_per_sec_min": throughput[0],
    "throughput_msgs_per_sec_max": throughput[-1],
    "throughput_msgs_per_sec_per_thread_median": statistics.median(throughput) / thread,
    "throughput_msgs_per_sec_per_thread_p95": percentile(throughput, 95) / thread,
    "base_url_used": max(set(bases), key=bases.count),
}
print(json.dumps(out, indent=2))
PY
    jq -c . "$RESULTS_DIR/t${t}.json" >> "$RESULTS_DIR/results.jsonl"
    local rps_median rps_p95
    rps_median="$(jq -r '.throughput_msgs_per_sec_median' "$RESULTS_DIR/t${t}.json")"
    rps_p95="$(jq -r '.throughput_msgs_per_sec_p95' "$RESULTS_DIR/t${t}.json")"
    local rps_per_thread_median
    rps_per_thread_median="$(jq -r '.throughput_msgs_per_sec_per_thread_median' "$RESULTS_DIR/t${t}.json")"
    echo "threads=$t total_median_rps=$rps_median total_p95_rps=$rps_p95 per_thread_median_rps=$rps_per_thread_median"
  done
}

write_summary() {
  {
    echo "# Runtime Webchat Throughput Summary"
    echo
    echo "- Bundle: \`$BUNDLE_DIR\`"
    echo "- Tenant: \`$EFFECTIVE_TENANT\`"
    echo "- Messages per thread: \`$MESSAGES_PER_THREAD\`"
    echo "- Repeats per thread: \`$REPEATS\`"
    echo
    echo "| Threads | Repeats | Total Msg/run | Success/run (med) | Fail/run (med) | Elapsed (ms, med) | Total RPS (med) | Total RPS (p95) | RPS/Thread (med) | Base URL Used |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    while IFS= read -r line; do
      threads="$(jq -r '.threads' <<<"$line")"
      repeats="$(jq -r '.repeats' <<<"$line")"
      total_requests_per_run="$(jq -r '.total_requests_per_run' <<<"$line")"
      ok="$(jq -r '.successful_requests_median' <<<"$line")"
      fail="$(jq -r '.failed_requests_median' <<<"$line")"
      elapsed="$(jq -r '.elapsed_ms_median' <<<"$line")"
      rps="$(jq -r '.throughput_msgs_per_sec_median' <<<"$line")"
      rps_p95="$(jq -r '.throughput_msgs_per_sec_p95' <<<"$line")"
      rps_per_thread="$(jq -r '.throughput_msgs_per_sec_per_thread_median' <<<"$line")"
      base_url_used="$(jq -r '.base_url_used // "n/a"' <<<"$line")"
      printf '| `%s` | `%s` | `%s` | `%s` | `%s` | `%s` | `%.3f` | `%.3f` | `%.3f` | `%s` |\n' "$threads" "$repeats" "$total_requests_per_run" "$ok" "$fail" "$elapsed" "$rps" "$rps_p95" "$rps_per_thread" "$base_url_used"
    done < "$RESULTS_DIR/results.jsonl"
    if [ -s "$RESULTS_DIR/results.jsonl" ]; then
      peak_threads="$(jq -s 'max_by(.throughput_msgs_per_sec_median).threads' "$RESULTS_DIR/results.jsonl")"
      peak_total_rps="$(jq -s 'max_by(.throughput_msgs_per_sec_median).throughput_msgs_per_sec_median' "$RESULTS_DIR/results.jsonl")"
      peak_per_thread_rps="$(jq -s 'max_by(.throughput_msgs_per_sec_median).throughput_msgs_per_sec_per_thread_median' "$RESULTS_DIR/results.jsonl")"
      echo
      echo "Peak total median throughput: \`$(printf "%.3f" "$peak_total_rps") msg/s\` at \`$peak_threads\` threads."
      echo
      echo "Per-thread median throughput at that peak: \`$(printf "%.3f" "$peak_per_thread_rps") msg/s/thread\`."
    fi
  } > "$SUMMARY_MD"
}

main() {
  need_cmd cargo
  need_cmd jq
  need_cmd python3
  if ! [[ "$REPEATS" =~ ^[0-9]+$ ]] || [ "$REPEATS" -lt 1 ]; then
    echo "RUNTIME_PERF_REPEATS must be an integer >= 1" >&2
    exit 1
  fi
  load_session
  ensure_runtime_ready
  mkdir -p "$RESULTS_DIR" "$LOG_DIR"
  configure_runtime_targets
  run_benchmark
  write_summary

  step "done"
  echo "results: $RESULTS_DIR"
  echo "summary: $SUMMARY_MD"
}

main "$@"
