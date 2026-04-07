use std::time::Duration;

use greentic_perf_harness::run_scenario;

#[cfg(unix)]
mod support;

#[cfg(unix)]
use support::{
    bundle_artifact_inspect_supported, bundle_build_supported, greentic_bundle_repo_ref,
    greentic_dev_repo_ref, gtc_repo_ref, smoke_bundle_fixture, smoke_pack_fixture,
    smoke_tier_fixture,
};

const SMOKE_COMMAND_TIMEOUT: Duration = Duration::from_secs(15);

#[cfg(unix)]
#[test]
fn smoke_cli_help_returns_output_before_timeout() {
    let result = run_scenario(
        "smoke-cli-help",
        gtc_repo_ref(),
        &["--help"],
        &smoke_pack_fixture(),
        1,
        SMOKE_COMMAND_TIMEOUT,
    )
    .expect("help scenario should run");

    assert!(result.success);
    assert!(!result.timed_out);
    assert_eq!(result.threads, 1);
    assert!(!result.stdout_tail.is_empty() || !result.stderr_tail.is_empty());
}

#[cfg(unix)]
#[test]
fn smoke_cli_version_returns_output_before_timeout() {
    let result = run_scenario(
        "smoke-cli-version",
        gtc_repo_ref(),
        &["version"],
        &smoke_pack_fixture(),
        1,
        SMOKE_COMMAND_TIMEOUT,
    )
    .expect("version scenario should run");

    assert!(result.success);
    assert!(!result.timed_out);
    assert!(
        result.stdout_tail.contains("gtc")
            || result.stdout_tail.contains("Greentic")
            || result.stdout_tail.contains("version")
    );
}

#[cfg(unix)]
#[test]
fn smoke_cli_small_commands_complete_before_timeout() {
    for (scenario_name, repo_ref, fixture, args) in [
        (
            "smoke-gtc-doctor",
            gtc_repo_ref(),
            smoke_pack_fixture(),
            vec!["doctor"],
        ),
        (
            "smoke-pack-build",
            greentic_dev_repo_ref(),
            smoke_pack_fixture(),
            vec!["pack", "build", "--in", "."],
        ),
        (
            "smoke-bundle-build",
            greentic_bundle_repo_ref(),
            smoke_bundle_fixture(),
            vec!["build"],
        ),
        (
            "smoke-bundle-artifact-inspect",
            greentic_bundle_repo_ref(),
            smoke_tier_fixture(),
            vec![
                "inspect",
                "--artifact",
                "artifacts/perf-smoke-bundle.gtbundle",
                "--json",
                "--offline",
            ],
        ),
    ] {
        if scenario_name == "smoke-bundle-build" && !bundle_build_supported() {
            eprintln!("skipping {scenario_name}: mksquashfs is not available");
            continue;
        }
        if scenario_name == "smoke-bundle-artifact-inspect" && !bundle_artifact_inspect_supported()
        {
            eprintln!("skipping {scenario_name}: unsquashfs is not available");
            continue;
        }

        let result = run_scenario(
            scenario_name,
            repo_ref,
            &args,
            &fixture,
            1,
            SMOKE_COMMAND_TIMEOUT,
        )
        .expect("smoke command should run");

        assert!(result.success, "expected success for {scenario_name}");
        assert!(!result.timed_out, "unexpected timeout for {scenario_name}");
        assert_eq!(result.threads, 1);
        if scenario_name == "smoke-bundle-artifact-inspect" {
            assert!(
                result.stdout_tail.contains("\"contents\": [")
                    || result.stdout_tail.contains("\"bundle-manifest.json\"")
                    || result.stdout_tail.contains("\"resolved/default.yaml\""),
                "expected artifact inspect output"
            );
        }
    }
}
