#![allow(dead_code)]

use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

use greentic_perf_harness::RepoRef;

static GENERATED_FIXTURES: OnceLock<()> = OnceLock::new();
static GENERATED_RUNTIME_FIXTURES: OnceLock<()> = OnceLock::new();

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("perf crate should live under the repo root")
        .to_path_buf()
}

pub fn ensure_generated_fixtures() {
    GENERATED_FIXTURES.get_or_init(|| {
        let status = Command::new("bash")
            .arg("scripts/check_fixtures.sh")
            .current_dir(repo_root())
            .status()
            .expect("fixture generation script should run");

        assert!(status.success(), "fixture generation script should succeed");
    });
}

pub fn generated_pack_fixture(tier: &str) -> PathBuf {
    repo_root()
        .join("fixtures-gen")
        .join(tier)
        .join("packs")
        .join(format!("perf-{tier}-pack"))
}

pub fn generated_bundle_fixture(tier: &str) -> PathBuf {
    repo_root()
        .join("fixtures-gen")
        .join(tier)
        .join("bundles")
        .join(format!("perf-{tier}-bundle"))
}

pub fn generated_tier_fixture(tier: &str) -> PathBuf {
    repo_root().join("fixtures-gen").join(tier)
}

pub fn generated_bundle_artifact(tier: &str) -> PathBuf {
    repo_root()
        .join("fixtures-gen")
        .join(tier)
        .join("artifacts")
        .join(format!("perf-{tier}-bundle.gtbundle"))
}

pub fn generated_runtime_bundle_fixture(name: &str) -> PathBuf {
    repo_root()
        .join("fixtures-gen")
        .join("runtime")
        .join("bundles")
        .join(name)
}

pub fn generated_runtime_bundle_artifact(name: &str) -> PathBuf {
    repo_root()
        .join("fixtures-gen")
        .join("runtime")
        .join("artifacts")
        .join(format!("{name}.gtbundle"))
}

pub fn smoke_pack_fixture() -> PathBuf {
    ensure_generated_fixtures();
    generated_pack_fixture("smoke")
}

pub fn smoke_bundle_fixture() -> PathBuf {
    ensure_generated_fixtures();
    generated_bundle_fixture("smoke")
}

pub fn smoke_tier_fixture() -> PathBuf {
    ensure_generated_fixtures();
    generated_tier_fixture("smoke")
}

pub fn runtime_fixture(name: &str) -> PathBuf {
    GENERATED_RUNTIME_FIXTURES.get_or_init(|| {
        let status = Command::new("bash")
            .arg("scripts/generate_runtime_fixtures.sh")
            .current_dir(repo_root())
            .status()
            .expect("runtime fixture generation script should run");
        assert!(
            status.success(),
            "runtime fixture generation should succeed"
        );
    });
    generated_runtime_bundle_fixture(name)
}

pub fn ensure_cli_available(binary: &str) {
    let status = Command::new(binary)
        .arg("--version")
        .status()
        .unwrap_or_else(|error| panic!("failed to execute {binary} --version: {error}"));
    assert!(status.success(), "{binary} --version should succeed");
}

pub fn repo_ref_for_binary(binary: &str) -> RepoRef {
    ensure_generated_fixtures();
    ensure_cli_available(binary);
    RepoRef::Path(PathBuf::from(binary))
}

pub fn gtc_repo_ref() -> RepoRef {
    repo_ref_for_binary("gtc")
}

pub fn greentic_dev_repo_ref() -> RepoRef {
    repo_ref_for_binary("greentic-dev")
}

pub fn greentic_bundle_repo_ref() -> RepoRef {
    repo_ref_for_binary("greentic-bundle")
}
