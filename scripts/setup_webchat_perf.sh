#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
RUN_ROOT="${RUNTIME_PERF_RUN_ROOT:-$ROOT_DIR/fixtures-gen/runtime-webchat-perf}"
WORKSPACE_DIR="$RUN_ROOT/workspace"
PACK_DIR="$WORKSPACE_DIR/packs/perf-runtime-webchat-pack"
BUNDLE_DIR="$WORKSPACE_DIR/bundles/perf-runtime-webchat-bundle"
ARTIFACTS_DIR="${RUNTIME_PERF_ARTIFACTS_DIR:-$ROOT_DIR/artifacts/runtime-webchat-perf}"
SCHEMA_DIR="$ARTIFACTS_DIR/schemas"
ANSWERS_DIR="$ARTIFACTS_DIR/answers"
LOG_DIR="$ARTIFACTS_DIR/logs"
SESSION_FILE="$ARTIFACTS_DIR/session.json"
RUNTIME_STDOUT="$LOG_DIR/runtime.stdout.log"
RUNTIME_STDERR="$LOG_DIR/runtime.stderr.log"

TENANT="${RUNTIME_PERF_TENANT:-default}"
TEAM="${RUNTIME_PERF_TEAM:-default}"
READINESS_TIMEOUT_SEC="${RUNTIME_PERF_READINESS_TIMEOUT_SEC:-60}"
INGRESS_BASE_URL="${RUNTIME_PERF_INGRESS_BASE_URL:-https://localhost:8080/va/1messaging/ingress/webchat/default}"

RUNTIME_PID=""
KEEP_RUNTIME=0
ENDPOINTS_PATH=""
EFFECTIVE_TENANT="$TENANT"
EFFECTIVE_TEAM="$TEAM"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

step() {
  printf "\n==> %s\n" "$1"
}

cleanup() {
  if [ "$KEEP_RUNTIME" -eq 0 ] && [ -n "$RUNTIME_PID" ] && kill -0 "$RUNTIME_PID" >/dev/null 2>&1; then
    kill "$RUNTIME_PID" >/dev/null 2>&1 || true
    wait "$RUNTIME_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

ensure_tooling() {
  need_cmd python3
  need_cmd jq
  need_cmd gtc
  need_cmd greentic-pack
  need_cmd greentic-bundle
}

stop_previous_runtime_if_present() {
  if [ ! -f "$SESSION_FILE" ]; then
    return 0
  fi

  local previous_pid
  previous_pid="$(jq -r '.runtime_pid // empty' "$SESSION_FILE" 2>/dev/null || true)"
  if [ -n "$previous_pid" ] && kill -0 "$previous_pid" >/dev/null 2>&1; then
    step "stop previous runtime pid $previous_pid"
    kill "$previous_pid" >/dev/null 2>&1 || true
    wait "$previous_pid" >/dev/null 2>&1 || true
  fi
}

derive_public_base_url() {
  python3 - "$INGRESS_BASE_URL" <<'PY'
import sys
from urllib.parse import urlsplit

url = urlsplit(sys.argv[1])
if not url.scheme or not url.netloc:
    raise SystemExit(f"invalid ingress url: {sys.argv[1]}")
print(f"{url.scheme}://{url.netloc}")
PY
}

write_answer_docs() {
  local pack_answers="$ANSWERS_DIR/pack.wizard.answers.json"
  local bundle_answers="$ANSWERS_DIR/bundle.wizard.answers.json"
  local setup_answers="$ANSWERS_DIR/bundle.setup.answers.json"
  local public_base_url

  public_base_url="$(derive_public_base_url)"

  python3 - "$pack_answers" "$bundle_answers" "$setup_answers" "$PACK_DIR" "$BUNDLE_DIR" "$TENANT" "$TEAM" "$public_base_url" <<'PY'
import json
import sys
from pathlib import Path

pack_answers_path = Path(sys.argv[1])
bundle_answers_path = Path(sys.argv[2])
setup_answers_path = Path(sys.argv[3])
pack_dir = Path(sys.argv[4])
bundle_dir = Path(sys.argv[5])
tenant = sys.argv[6]
team = sys.argv[7]
public_base_url = sys.argv[8]

pack_doc = {
    "wizard_id": "greentic-pack.wizard.run",
    "schema_id": "greentic-pack.wizard.answers",
    "schema_version": "1.0.0",
    "locale": "en",
    "answers": {
        "create_pack_id": "perf.runtime.webchat.pack",
        "create_pack_scaffold": True,
        "dry_run": False,
        "mode": "generated-apply",
        "pack_dir": str(pack_dir),
        "run_build": True,
        "run_delegate_component": False,
        "run_delegate_flow": False,
        "run_doctor": True,
        "selected_actions": [
            "main.create_application_pack",
            "generated.create_application_pack",
            "pipeline.update_validate",
            "pipeline.sign_prompt.skip",
        ],
        "sign": False,
    },
    "locks": {},
}

bundle_doc = {
    "wizard_id": "greentic-bundle.wizard.run",
    "schema_id": "greentic-bundle.wizard.answers",
    "schema_version": "1.0.0",
    "locale": "en",
    "answers": {
        "access_rules": [
            {
                "policy": "allow",
                "rule_path": "perf-runtime-webchat-pack",
                "tenant": tenant,
            }
        ],
        "advanced_setup": False,
        "app_pack_entries": [
            {
                "detected_kind": "local_file",
                "display_name": "Perf Runtime Webchat Pack",
                "mapping": {"scope": "global"},
                "pack_id": "perf-runtime-webchat-pack",
                "reference": "./packs/perf-runtime-webchat-pack",
            }
        ],
        "app_packs": ["./packs/perf-runtime-webchat-pack"],
        "bundle_id": "perf-runtime-webchat-bundle",
        "bundle_name": "perf-runtime-webchat-bundle",
        "capabilities": [],
        "export_intent": False,
        "extension_provider_entries": [
            {
                "detected_kind": "oci",
                "display_name": "WebChat",
                "provider_id": "messaging-webchat",
                "reference": "oci://ghcr.io/greenticai/packs/messaging/messaging-webchat:latest",
                "version": "latest",
            }
        ],
        "extension_providers": [
            "oci://ghcr.io/greenticai/packs/messaging/messaging-webchat:latest"
        ],
        "mode": "create",
        "output_dir": str(bundle_dir),
        "remote_catalogs": [],
        "setup_answers": {},
        "setup_execution_intent": False,
        "setup_specs": {},
    },
    "locks": {},
}

setup_doc = {
    "bundle_source": str(bundle_dir),
    "env": "dev",
    "tenant": tenant,
    "team": team,
    "platform_setup": {
        "static_routes": {
            "public_web_enabled": True,
            "public_base_url": public_base_url,
            "public_surface_policy": "enabled",
            "default_route_prefix_policy": "pack_declared",
            "tenant_path_policy": "pack_declared",
        }
    },
    "setup_answers": {
        "messaging-webchat": {
            "mode": "directline",
            "public_base_url": public_base_url,
            "jwt_signing_key": "perf-runtime-webchat-dev-key",
        }
    },
}

pack_answers_path.parent.mkdir(parents=True, exist_ok=True)
bundle_answers_path.parent.mkdir(parents=True, exist_ok=True)
setup_answers_path.parent.mkdir(parents=True, exist_ok=True)
pack_answers_path.write_text(json.dumps(pack_doc, indent=2))
bundle_answers_path.write_text(json.dumps(bundle_doc, indent=2))
setup_answers_path.write_text(json.dumps(setup_doc, indent=2))
PY
}

prepare_pack_and_bundle() {
  step "capture wizard schemas"
  greentic-pack wizard --schema > "$SCHEMA_DIR/greentic-pack.wizard.schema.json"
  greentic-bundle wizard --schema > "$SCHEMA_DIR/greentic-bundle.wizard.schema.json"

  step "write wizard/setup answer docs"
  write_answer_docs

  step "create app pack via greentic-pack wizard --answers"
  greentic-pack wizard validate --answers "$ANSWERS_DIR/pack.wizard.answers.json"
  greentic-pack wizard run --answers "$ANSWERS_DIR/pack.wizard.answers.json"

  mkdir -p "$PACK_DIR/components"
  cat > "$PACK_DIR/components/templates.txt" <<'EOF'
templates component placeholder used for runtime perf fixture identity
EOF
  cat > "$PACK_DIR/components/qa.txt" <<'EOF'
qa component placeholder used for runtime perf fixture identity
EOF
  cat > "$PACK_DIR/components/adaptive-card.txt" <<'EOF'
adaptive-card component placeholder used for runtime perf fixture identity
EOF

  step "create bundle via greentic-bundle wizard --answers"
  mkdir -p "$BUNDLE_DIR/packs"
  rm -rf "$BUNDLE_DIR/packs/perf-runtime-webchat-pack"
  cp -R "$PACK_DIR" "$BUNDLE_DIR/packs/perf-runtime-webchat-pack"
  greentic-bundle wizard validate --answers "$ANSWERS_DIR/bundle.wizard.answers.json" --mode create
  greentic-bundle wizard run --answers "$ANSWERS_DIR/bundle.wizard.answers.json" --mode create --locale en

  step "configure bundle via gtc setup --answers"
  gtc setup "$BUNDLE_DIR" \
    --answers "$ANSWERS_DIR/bundle.setup.answers.json" \
    --tenant "$TENANT" \
    --team "$TEAM"
}

latest_endpoints_path() {
  find "$BUNDLE_DIR/state/runtime" -type f -path '*/endpoints.json' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-
}

wait_for_runtime() {
  local deadline=$((SECONDS + READINESS_TIMEOUT_SEC))
  local used_fallback=0

  step "start runtime with gtc start ./bundle"
  gtc start "$BUNDLE_DIR" >"$RUNTIME_STDOUT" 2>"$RUNTIME_STDERR" &
  RUNTIME_PID="$!"
  echo "runtime pid: $RUNTIME_PID"

  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! kill -0 "$RUNTIME_PID" >/dev/null 2>&1; then
      if [ "$used_fallback" -eq 0 ] && grep -q "unexpected argument '--admin-port'" "$RUNTIME_STDERR"; then
        echo "gtc start hit known --admin-port mismatch; retrying with greentic-start fallback"
        greentic-start start --bundle "$BUNDLE_DIR" --nats off --cloudflared off --ngrok off >"$RUNTIME_STDOUT" 2>"$RUNTIME_STDERR" &
        RUNTIME_PID="$!"
        used_fallback=1
        sleep 1
        continue
      fi
      echo "runtime exited before readiness; see $RUNTIME_STDERR" >&2
      exit 1
    fi

    local endpoints_path
    endpoints_path="$(latest_endpoints_path || true)"
    if [ -n "$endpoints_path" ] && [ -f "$endpoints_path" ]; then
      ENDPOINTS_PATH="$endpoints_path"
      echo "runtime endpoints: $endpoints_path"
      return 0
    fi
    sleep 1
  done

  echo "runtime did not become ready within ${READINESS_TIMEOUT_SEC}s; expected state/runtime/**/endpoints.json" >&2
  exit 1
}

write_session() {
  jq -n \
    --arg runtime_pid "$RUNTIME_PID" \
    --arg bundle_dir "$BUNDLE_DIR" \
    --arg endpoints_path "$ENDPOINTS_PATH" \
    --arg tenant "$EFFECTIVE_TENANT" \
    --arg team "$EFFECTIVE_TEAM" \
    --arg ingress_base_url "$INGRESS_BASE_URL" \
    --arg runtime_stdout "$RUNTIME_STDOUT" \
    --arg runtime_stderr "$RUNTIME_STDERR" \
    '{
      runtime_pid: ($runtime_pid | tonumber),
      bundle_dir: $bundle_dir,
      endpoints_path: $endpoints_path,
      tenant: $tenant,
      team: $team,
      ingress_base_url: $ingress_base_url,
      runtime_stdout: $runtime_stdout,
      runtime_stderr: $runtime_stderr
    }' > "$SESSION_FILE"
}

main() {
  ensure_tooling
  mkdir -p "$WORKSPACE_DIR/packs" "$WORKSPACE_DIR/bundles" "$SCHEMA_DIR" "$ANSWERS_DIR" "$LOG_DIR"
  rm -rf "$PACK_DIR" "$BUNDLE_DIR"
  stop_previous_runtime_if_present
  prepare_pack_and_bundle
  wait_for_runtime
  write_session
  KEEP_RUNTIME=1

  step "setup complete"
  echo "session: $SESSION_FILE"
  echo "bundle: $BUNDLE_DIR"
  echo "runtime pid: $RUNTIME_PID"
  echo "tenant/team: $EFFECTIVE_TENANT/$EFFECTIVE_TEAM"
}

main "$@"
