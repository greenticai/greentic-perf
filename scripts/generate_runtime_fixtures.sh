#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/fixtures-src/runtime"
GEN_DIR="$ROOT_DIR/fixtures-gen/runtime"
ANSWERS="$SRC_DIR/qa-template-worker/answers.json"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

ensure_tooling() {
  if ! command -v gtc >/dev/null 2>&1; then
    bash "$ROOT_DIR/scripts/bootstrap_gtc.sh"
  fi
  need_cmd python3
  need_cmd gtc
}

cleanup_wizard_runs() {
  local wizard_root="$ROOT_DIR/.greentic/wizard"
  if [ -d "$wizard_root" ]; then
    find "$wizard_root" -maxdepth 1 -mindepth 1 -type d -name 'run-*' -exec rm -rf {} +
  fi
}

bundle_name() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$ANSWERS"
}

bundle_title() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["values"]["bundle_name"])' "$ANSWERS"
}

resolve_built_artifact() {
  local build_output="$1"
  local bundle_name="$2"

  if [ -f "$build_output" ]; then
    printf '%s\n' "$build_output"
    return 0
  fi

  if [ -d "$build_output" ]; then
    if [ -f "$build_output/dist/$bundle_name.gtbundle" ]; then
      printf '%s\n' "$build_output/dist/$bundle_name.gtbundle"
      return 0
    fi

    found="$(find "$build_output" -type f -name "$bundle_name.gtbundle" | head -n 1)"
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
      return 0
    fi
  fi

  return 1
}

clear_local_only_runtime_artifacts() {
  local bundle_dir="$1"
  local tenant="$2"
  local team="$3"

  rm -f "$bundle_dir/logs/cloudflared.log"
  rm -f "$bundle_dir/state/pids/$tenant.$team/cloudflared.pid"
  rm -f "$bundle_dir/state/runtime/$tenant.$team/resolved/cloudflared.json"
}

write_runtime_answers() {
  local bundle_dir="$1"
  local wizard_answers_path="$2"
  local setup_answers_path="$3"

  python3 - <<'PY' "$ANSWERS" "$bundle_dir" "$wizard_answers_path" "$setup_answers_path"
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text())
bundle_dir = Path(sys.argv[2])
wizard_answers_path = Path(sys.argv[3])
setup_answers_path = Path(sys.argv[4])
values = source["values"]

wizard_doc = {
    "wizard_id": "greentic-dev.wizard.launcher.main",
    "schema_id": "greentic-dev.launcher.main",
    "schema_version": "1.0.0",
    "locale": "en",
    "answers": {
        "selected_action": "bundle",
        "delegate_answer_document": {
            "wizard_id": "greentic-bundle.wizard.run",
            "schema_id": "greentic-bundle.wizard.answers",
            "schema_version": "1.0.0",
            "locale": "en",
            "answers": {
                "access_rules": [],
                "advanced_setup": False,
                "app_pack_entries": [],
                "app_packs": [],
                "bundle_id": values["bundle_id"],
                "bundle_name": values["bundle_name"],
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
            "locks": {
                "cache_policy": "workspace-local",
                "catalogs": [],
                "execution": "execute",
                "lock_file": "bundle.lock.json",
                "requested_mode": "create",
                "setup_state_files": [],
                "workspace_root": "bundle.yaml",
            },
        },
    },
    "locks": {},
}

setup_doc = {
    "bundle_source": str(bundle_dir),
    "env": "dev",
    "tenant": values.get("tenant", "demo"),
    "team": values.get("team", "default"),
    "platform_setup": {
        "static_routes": {
            "public_web_enabled": False,
            "public_base_url": None,
            "public_surface_policy": "disabled",
            "default_route_prefix_policy": "pack_declared",
            "tenant_path_policy": "pack_declared",
        }
    },
    "setup_answers": {
        "messaging-webchat": {
            "mode": values.get("webchat_mode", "directline"),
            "public_base_url": values.get("public_base_url", "http://127.0.0.1:8080"),
            "jwt_signing_key": values.get("jwt_signing_key", "qa-template-worker-dev-key"),
        }
    },
}

wizard_answers_path.parent.mkdir(parents=True, exist_ok=True)
wizard_answers_path.write_text(json.dumps(wizard_doc, indent=2))
setup_answers_path.write_text(json.dumps(setup_doc, indent=2))
PY
}

main() {
  ensure_tooling
  cleanup_wizard_runs

  local name title tenant team bundle_dir artifact_dir artifact_path wizard_answers_path setup_answers_path staging_dir staging_artifact built_artifact
  name="$(bundle_name)"
  title="$(bundle_title)"
  tenant="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["values"].get("tenant", "demo"))' "$ANSWERS")"
  team="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["values"].get("team", "default"))' "$ANSWERS")"
  bundle_dir="$GEN_DIR/bundles/$name"
  artifact_dir="$GEN_DIR/artifacts"
  artifact_path="$artifact_dir/$name.gtbundle"
  staging_dir="$GEN_DIR/.staging/$name"
  staging_artifact="$artifact_dir/$name.gtbundle.tmp"
  wizard_answers_path="$GEN_DIR/.wizard/$name.bundle.answers.json"
  setup_answers_path="$GEN_DIR/.wizard/$name.bundle.setup.answers.json"

  rm -rf "$staging_dir" "$staging_artifact"
  mkdir -p "$staging_dir" "$artifact_dir" "$GEN_DIR/.wizard" "$GEN_DIR/.staging"

  echo "Generating runtime fixture bundle: $name"
  write_runtime_answers "$staging_dir" "$wizard_answers_path" "$setup_answers_path"
  if gtc wizard apply --answers "$wizard_answers_path" --yes --non-interactive --locale en &&
    gtc setup --answers "$setup_answers_path" "$staging_dir" &&
    gtc setup bundle build --bundle "$staging_dir" --out "$staging_artifact" --skip-doctor; then
    built_artifact="$(resolve_built_artifact "$staging_artifact" "$name")" || {
      echo "error: unable to locate built runtime artifact under $staging_artifact" >&2
      exit 1
    }
    clear_local_only_runtime_artifacts "$staging_dir" "$tenant" "$team"
    rm -rf "$bundle_dir"
    rm -rf "$artifact_path"
    mv "$staging_dir" "$bundle_dir"
    cp "$built_artifact" "$artifact_path"
    rm -rf "$staging_artifact"
  else
    rm -rf "$staging_dir" "$staging_artifact"
    if [ -d "$bundle_dir" ] && [ -f "$artifact_path" ]; then
      echo "warning: runtime fixture regeneration failed; reusing cached runtime fixture at $bundle_dir" >&2
    else
      echo "error: runtime fixture generation failed and no cached runtime fixture is available" >&2
      exit 1
    fi
  fi

  test -f "$artifact_path"
  cleanup_wizard_runs
  echo "Generated runtime fixture bundle at $bundle_dir"
  echo "Generated runtime artifact at $artifact_path"
}

main "$@"
