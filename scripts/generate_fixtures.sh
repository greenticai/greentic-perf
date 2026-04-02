#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/fixtures-src"
GEN_DIR="$ROOT_DIR/fixtures-gen"
LOCK_DIR="$GEN_DIR/.lock"

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

validate_tier_arg() {
  case "$1" in
    smoke|medium|heavy) ;;
    *)
      echo "unsupported fixture tier: $1" >&2
      exit 1
      ;;
  esac
}

acquire_lock() {
  mkdir -p "$GEN_DIR"
  while ! mkdir "$LOCK_DIR" >/dev/null 2>&1; do
    sleep 1
  done
  trap 'rmdir "$LOCK_DIR"' EXIT
}

cleanup_wizard_runs() {
  local wizard_root="$ROOT_DIR/.greentic/wizard"
  if [ -d "$wizard_root" ]; then
    find "$wizard_root" -maxdepth 1 -mindepth 1 -type d -name 'run-*' -exec rm -rf {} +
  fi
}

generate_tier() {
  local tier="$1"
  python3 - "$ROOT_DIR" "$SRC_DIR/$tier" "$GEN_DIR/$tier" <<'PY'
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
src_tier = Path(sys.argv[2])
out_tier = Path(sys.argv[3])


def load_answers(kind: str) -> dict:
    return json.loads((src_tier / kind / "answers.json").read_text())


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def run(args: list[str], cwd: Path | None = None) -> None:
    env = os.environ.copy()
    env.setdefault("LC_ALL", "C.UTF-8")
    env.setdefault("LANG", "C.UTF-8")
    subprocess.run(args, cwd=cwd, env=env, check=True)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def wrap_launcher(action: str, delegate_answer_document: dict) -> dict:
    return {
        "wizard_id": "greentic-dev.wizard.launcher.main",
        "schema_id": "greentic-dev.launcher.main",
        "schema_version": "1.0.0",
        "locale": delegate_answer_document.get("locale", "en"),
        "answers": {
            "selected_action": action,
            "delegate_answer_document": delegate_answer_document,
        },
        "locks": {},
    }


def tier_for_pack_name(pack_name: str) -> str:
    if pack_name.startswith("perf-smoke-"):
        return "smoke"
    if pack_name.startswith("perf-medium-"):
        return "medium"
    if pack_name.startswith("perf-heavy-"):
        return "heavy"
    raise ValueError(f"cannot infer tier for pack {pack_name}")


def build_pack_answer_document(answers: dict, pack_dir: Path) -> dict:
    values = answers["values"]
    delegate = {
        "wizard_id": "greentic-pack.wizard.run",
        "schema_id": "greentic-pack.wizard.answers",
        "schema_version": "1.0.0",
        "locale": "en",
        "answers": {
            "create_pack_id": values["pack_id"],
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
    return wrap_launcher("pack", delegate)


def enrich_pack(tier: str, answers: dict, pack_root: Path) -> None:
    values = answers["values"]
    flow_count = max(1, int(values.get("flow_count", 1)))
    component_count = max(1, int(values.get("component_count", 1)))
    asset_count = max(1, int(values.get("asset_count", 1)))
    (pack_root / "flows").mkdir(exist_ok=True)
    (pack_root / "components").mkdir(exist_ok=True)
    (pack_root / "assets").mkdir(exist_ok=True)

    for index in range(2, flow_count + 1):
        (pack_root / "flows" / f"flow-{index:02d}.ygtc").write_text(
            "\n".join(
                [
                    f"id: flow-{index:02d}",
                    "type: messaging",
                    "nodes: {}",
                    "",
                ]
            )
        )

    for index in range(1, component_count + 1):
        (pack_root / "components" / f"component-{index:02d}.txt").write_text(
            f"{values['pack_name']} component {index:02d} for {tier}\n"
        )

    for index in range(1, asset_count + 1):
        (pack_root / "assets" / f"asset-{index:02d}.txt").write_text(
            f"{values['pack_name']} asset {index:02d} for {tier}\n"
        )


def write_pack(tier: str, answers: dict) -> None:
    pack_root = out_tier / "packs" / answers["name"]
    ensure_clean_dir(pack_root)
    answer_doc_path = out_tier / ".wizard" / f"{answers['name']}.pack.answers.json"
    write_json(answer_doc_path, build_pack_answer_document(answers, pack_root))
    run(
        [
            "gtc",
            "wizard",
            "apply",
            "--answers",
            str(answer_doc_path),
            "--yes",
            "--non-interactive",
            "--locale",
            "en",
        ],
        cwd=root,
    )
    enrich_pack(tier, answers, pack_root)


def copy_pack_for_bundle(bundle_root: Path, pack_name: str) -> None:
    source_pack = (
        root
        / "fixtures-gen"
        / tier_for_pack_name(pack_name)
        / "packs"
        / pack_name
    )
    target_pack = bundle_root / "packs" / pack_name
    if target_pack.exists():
        shutil.rmtree(target_pack)
    shutil.copytree(source_pack, target_pack)


def build_bundle_answer_document(answers: dict, bundle_root: Path) -> dict:
    values = answers["values"]
    entries = []
    refs = []
    rules = []
    for pack_ref in values["pack_refs"]:
        pack_name = Path(pack_ref["local_path"]).parts[-2]
        reference = f"./packs/{pack_name}"
        entries.append(
            {
                "detected_kind": "local_file",
                "display_name": pack_name.replace("-", " ").title(),
                "mapping": {"scope": "global"},
                "pack_id": pack_name,
                "reference": reference,
            }
        )
        refs.append(reference)
        rules.append(
            {
                "policy": "public",
                "rule_path": pack_name,
                "tenant": "default",
            }
        )

    delegate = {
        "wizard_id": "greentic-bundle.wizard.run",
        "schema_id": "greentic-bundle.wizard.answers",
        "schema_version": "1.0.0",
        "locale": "en",
        "answers": {
            "access_rules": rules,
            "advanced_setup": False,
            "app_pack_entries": entries,
            "app_packs": refs,
            "bundle_id": values["bundle_id"],
            "bundle_name": values["bundle_name"],
            "capabilities": ["greentic.cap.bundle_assets.read.v1"],
            "export_intent": False,
            "extension_provider_entries": [],
            "extension_providers": [],
            "mode": "create",
            "output_dir": str(bundle_root),
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
    }
    return wrap_launcher("bundle", delegate)


def enrich_bundle(tier: str, answers: dict, bundle_root: Path) -> None:
    values = answers["values"]
    (bundle_root / "assets").mkdir(exist_ok=True)
    for index, pack_ref in enumerate(values["pack_refs"], start=1):
        pack_name = Path(pack_ref["local_path"]).parts[-2]
        (bundle_root / "assets" / f"asset-{index:02d}.txt").write_text(
            f"{values['bundle_name']} bundle asset tied to {pack_name} for {tier}\n"
        )


def build_bundle_setup_answers(bundle_root: Path) -> dict:
    return {
        "bundle_source": str(bundle_root),
        "env": "dev",
        "tenant": "demo",
        "team": "default",
        "platform_setup": {
            "static_routes": {
                "public_web_enabled": False,
                "public_surface_policy": "disabled",
                "default_route_prefix_policy": "pack_declared",
                "tenant_path_policy": "pack_declared",
            }
        },
        "setup_answers": {},
    }


def write_bundle(tier: str, answers: dict) -> None:
    bundle_root = out_tier / "bundles" / answers["name"]
    ensure_clean_dir(bundle_root)
    (bundle_root / "packs").mkdir(parents=True, exist_ok=True)
    for pack_ref in answers["values"]["pack_refs"]:
        copy_pack_for_bundle(bundle_root, Path(pack_ref["local_path"]).parts[-2])
    answer_doc_path = out_tier / ".wizard" / f"{answers['name']}.bundle.answers.json"
    write_json(answer_doc_path, build_bundle_answer_document(answers, bundle_root))
    run(
        [
            "gtc",
            "wizard",
            "apply",
            "--answers",
            str(answer_doc_path),
            "--yes",
            "--non-interactive",
            "--locale",
            "en",
        ],
        cwd=root,
    )
    enrich_bundle(tier, answers, bundle_root)
    setup_answers_path = out_tier / ".wizard" / f"{answers['name']}.bundle.setup.answers.json"
    write_json(setup_answers_path, build_bundle_setup_answers(bundle_root))
    run(
        [
            "gtc",
            "setup",
            "--answers",
            str(setup_answers_path),
            str(bundle_root),
        ],
        cwd=root,
    )
    artifact_path = out_tier / "artifacts" / f"{answers['name']}.gtbundle"
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "greentic-bundle",
            "build",
            "--root",
            str(bundle_root),
            "--output",
            str(artifact_path),
            "--locale",
            "en",
        ],
        cwd=root,
    )


pack_answers = load_answers("pack")
bundle_answers = load_answers("bundle")
out_tier.mkdir(parents=True, exist_ok=True)
write_pack(src_tier.name, pack_answers)
write_bundle(src_tier.name, bundle_answers)
PY
}

main() {
  local requested_tiers=("$@")
  local tiers=()
  local tier

  if [ "${#requested_tiers[@]}" -eq 0 ]; then
    requested_tiers=(smoke medium heavy)
  fi

  for tier in "${requested_tiers[@]}"; do
    validate_tier_arg "$tier"
    case "$tier" in
      smoke)
        tiers+=(smoke)
        ;;
      medium)
        tiers+=(smoke medium)
        ;;
      heavy)
        tiers+=(smoke medium heavy)
        ;;
    esac
  done

  local unique_tiers=()
  for tier in "${tiers[@]}"; do
    case " ${unique_tiers[*]} " in
      *" $tier "*) ;;
      *) unique_tiers+=("$tier") ;;
    esac
  done

  ensure_tooling
  acquire_lock
  cleanup_wizard_runs

  for tier in "${unique_tiers[@]}"; do
    rm -rf "$GEN_DIR/$tier"
    generate_tier "$tier"
  done

  cleanup_wizard_runs
  echo "Generated real perf fixtures:"
  for tier in "${unique_tiers[@]}"; do
    find "$GEN_DIR/$tier" -maxdepth 3 | sort
  done
}

main "$@"
