use std::time::Duration;

use greentic_perf_harness::run_scenario;

#[cfg(unix)]
mod support;

#[cfg(unix)]
use support::{greentic_dev_repo_ref, smoke_pack_fixture};

#[cfg(unix)]
#[test]
fn smoke_threads_matrix_runs_pack_build() {
    for threads in [1usize, 4, 8] {
        let result = run_scenario(
            &format!("smoke-pack-build-t{threads}"),
            greentic_dev_repo_ref(),
            &["pack", "build", "--in", "."],
            &smoke_pack_fixture(),
            threads,
            Duration::from_secs(2),
        )
        .expect("threaded smoke scenario should run");

        assert!(
            result.success,
            "expected success for thread count {threads}"
        );
        assert!(
            !result.timed_out,
            "unexpected timeout for thread count {threads}"
        );
        assert_eq!(result.threads, threads);
    }
}
