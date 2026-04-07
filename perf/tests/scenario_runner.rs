use std::time::Duration;

use greentic_perf_harness::{RepoRef, run_scenario};

#[cfg(unix)]
mod support;

#[cfg(unix)]
use support::{ensure_generated_fixtures, generated_pack_fixture};

const SCENARIO_COMMAND_TIMEOUT: Duration = Duration::from_secs(10);

#[cfg(unix)]
#[test]
fn runs_a_command_against_a_copied_fixture_and_serializes_the_result() {
    ensure_generated_fixtures();

    let result = run_scenario(
        "bash-fixture-check",
        RepoRef::Path("/bin/bash".into()),
        &[
            "-lc",
            "printf 'threads:%s\\n' \"${GTC_THREADS:-unset}\"; find . -maxdepth 2 -type f >/dev/null; printf 'fixture:%s\\n' \"$PWD\"",
        ],
        &generated_pack_fixture("smoke"),
        4,
        SCENARIO_COMMAND_TIMEOUT,
    )
    .expect("scenario should run");

    assert!(result.success);
    assert!(!result.timed_out);
    assert_eq!(result.exit_code, Some(0));
    assert!(result.stdout_tail.contains("threads:4"));
    assert!(result.working_directory.ends_with("perf-smoke-pack"));
    assert_eq!(result.last_completed_phase, "command_end");
    assert_eq!(
        result
            .phases
            .iter()
            .map(|phase| phase.phase.as_str())
            .collect::<Vec<_>>(),
        vec![
            "checkout/setup",
            "fixture_prep",
            "command_start",
            "command_end"
        ]
    );

    let json = result.to_json_pretty().expect("result json");
    assert!(json.contains("\"scenario_name\": \"bash-fixture-check\""));
    assert!(json.contains("\"success\": true"));
    assert!(json.contains("\"last_completed_phase\": \"command_end\""));
}

#[cfg(unix)]
#[test]
fn times_out_long_running_commands() {
    ensure_generated_fixtures();

    let result = run_scenario(
        "timeout-case",
        RepoRef::Path("/bin/bash".into()),
        &["-lc", "printf 'starting\\n'; sleep 2"],
        &generated_pack_fixture("smoke"),
        1,
        Duration::from_millis(150),
    )
    .expect("scenario should produce a timeout result");

    assert!(!result.success);
    assert!(result.timed_out);
    assert_eq!(result.exit_code, None);
    assert_eq!(result.last_completed_phase, "timeout");
    assert_eq!(
        result.phases.last().map(|phase| phase.phase.as_str()),
        Some("timeout")
    );
    assert_eq!(
        result
            .phases
            .iter()
            .map(|phase| phase.phase.as_str())
            .collect::<Vec<_>>(),
        vec!["checkout/setup", "fixture_prep", "command_start", "timeout"]
    );
}

#[test]
fn rejects_zero_threads() {
    let err = run_scenario(
        "invalid-threads",
        RepoRef::GitRef("main".to_owned()),
        &["--help"],
        &{
            ensure_generated_fixtures();
            generated_pack_fixture("smoke")
        },
        0,
        Duration::from_secs(1),
    )
    .expect_err("zero threads should fail");

    assert_eq!(err.kind(), std::io::ErrorKind::InvalidInput);
}
