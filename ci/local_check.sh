#!/usr/bin/env bash

set -euo pipefail

mode="${1:-full}"

step() {
  printf '\n==> %s\n' "$1"
}

list_publishable_crates() {
  cargo metadata --no-deps --format-version 1 | perl -MJSON::PP -e '
    local $/;
    my $data = decode_json(<STDIN>);
    for my $pkg (@{$data->{packages}}) {
      next if defined($pkg->{publish}) && ref($pkg->{publish}) eq q(JSON::PP::Boolean) && !$pkg->{publish};
      next if defined($pkg->{publish}) && ref($pkg->{publish}) eq q(ARRAY) && !@{$pkg->{publish}};
      print $pkg->{name}, "\t", $pkg->{manifest_path}, "\n";
    }
  '
}

assert_packaged_assets() {
  crate_name="$1"
  package_list="$2"

  printf '%s\n' "$package_list" | grep -Eq '(^|/)Cargo\.toml$' || {
    printf 'Missing Cargo.toml in packaged crate for %s\n' "$crate_name" >&2
    return 1
  }
  printf '%s\n' "$package_list" | grep -Eq '(^|/)README' || {
    printf 'Missing README in packaged crate for %s\n' "$crate_name" >&2
    return 1
  }
  printf '%s\n' "$package_list" | grep -Eq '(^|/)LICENSE' || {
    printf 'Missing LICENSE in packaged crate for %s\n' "$crate_name" >&2
    return 1
  }
  printf '%s\n' "$package_list" | grep -Eq '(^|/)src/' || {
    printf 'Missing src/ files in packaged crate for %s\n' "$crate_name" >&2
    return 1
  }
}

run_packaging_checks() {
  dirty_flag=""
  if [ -z "${CI:-}" ]; then
    dirty_flag="--allow-dirty"
  fi

  while IFS="$(printf '\t')" read -r crate_name manifest_path; do
    [ -n "$crate_name" ] || continue
    manifest_dir=$(dirname "$manifest_path")

    step "Packaging checks for $crate_name"
    cargo package --manifest-path "$manifest_path" --no-verify -p "$crate_name" $dirty_flag
    cargo package --manifest-path "$manifest_path" -p "$crate_name" $dirty_flag

    package_list=$(cargo package --manifest-path "$manifest_path" --list -p "$crate_name" $dirty_flag)
    assert_packaged_assets "$crate_name" "$package_list"

    if [ -d "$manifest_dir/wit" ] || [ -d "$manifest_dir/schemas" ] || [ -d "$manifest_dir/templates" ]; then
      printf '%s\n' "$package_list" | grep -Eq '(^|/)(wit|schemas|templates)/' || {
        printf 'Expected runtime assets missing from packaged crate for %s\n' "$crate_name" >&2
        return 1
      }
    fi

    cargo publish --manifest-path "$manifest_path" -p "$crate_name" --dry-run $dirty_flag
  done < <(list_publishable_crates)
}

case "$mode" in
  full)
    step "cargo fmt"
    cargo fmt --all -- --check

    step "cargo clippy"
    cargo clippy --workspace --all-targets --all-features -- -D warnings

    step "fixture generation"
    bash scripts/check_fixtures.sh

    step "cargo test"
    cargo test --workspace --all-features

    step "cargo build"
    cargo build --workspace --all-features

    step "cargo doc"
    cargo doc --workspace --no-deps --all-features

    run_packaging_checks
    ;;
  package-only)
    run_packaging_checks
    ;;
  *)
    printf 'Unsupported mode: %s\n' "$mode" >&2
    exit 1
    ;;
esac
