use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use greentic_perf_harness::run_scenario;
use serde::Deserialize;

#[cfg(unix)]
mod support;

#[cfg(unix)]
use support::{
    bundle_artifact_inspect_supported, bundle_build_supported, repo_ref_for_binary, repo_root,
};

#[derive(Debug, Deserialize)]
struct BudgetFile {
    scenarios: Vec<BudgetScenario>,
}

#[derive(Debug, Deserialize)]
struct BudgetScenario {
    name: String,
    binary: String,
    args: Vec<String>,
    fixture: PathBuf,
    budgets: BTreeMap<String, BudgetThreshold>,
    scaling: ScalingBudget,
}

#[derive(Debug, Deserialize)]
struct BudgetThreshold {
    max_ms: u128,
}

#[derive(Debug, Deserialize)]
struct ScalingBudget {
    max_regression_vs_t1_pct: f64,
    max_regression_vs_prev_pct: f64,
}

#[cfg(unix)]
#[test]
#[ignore = "perf budgets are environment-sensitive and should only run on a calibrated perf runner"]
fn validates_perf_budgets_and_scaling() {
    support::ensure_generated_fixtures();
    let budgets = load_budget_file();

    for scenario in budgets.scenarios {
        if scenario.binary == "greentic-bundle"
            && scenario.args.first().map(String::as_str) == Some("build")
            && !bundle_build_supported()
        {
            eprintln!(
                "skipping budget scenario {}: mksquashfs is not available",
                scenario.name
            );
            continue;
        }
        if scenario.binary == "greentic-bundle"
            && scenario.args.first().map(String::as_str) == Some("inspect")
            && !bundle_artifact_inspect_supported()
        {
            eprintln!(
                "skipping budget scenario {}: unsquashfs is not available",
                scenario.name
            );
            continue;
        }

        let fixture = repo_root().join(&scenario.fixture);
        let mut ordered_threads: Vec<usize> = scenario
            .budgets
            .keys()
            .map(|key| {
                key.parse::<usize>().unwrap_or_else(|error| {
                    panic!("invalid thread key '{}' in perf-budgets.yaml: {error}", key)
                })
            })
            .collect();
        ordered_threads.sort_unstable();
        let scenario_timeout = Duration::from_secs(30);

        let mut measurements = BTreeMap::new();

        for threads in ordered_threads.iter().copied() {
            let result = run_scenario(
                &format!("{}-t{threads}", scenario.name),
                repo_ref_for_binary(&scenario.binary),
                &scenario.args.iter().map(String::as_str).collect::<Vec<_>>(),
                &fixture,
                threads,
                scenario_timeout,
            )
            .unwrap_or_else(|error| {
                panic!(
                    "budget scenario {} failed to execute for threads {}: {error}",
                    scenario.name, threads
                )
            });

            assert!(
                result.success,
                "budget scenario {} did not succeed for threads {}",
                scenario.name, threads
            );
            assert!(
                !result.timed_out,
                "budget scenario {} timed out for threads {}",
                scenario.name, threads
            );

            let threshold = scenario
                .budgets
                .get(&threads.to_string())
                .expect("thread threshold should exist");
            assert!(
                result.wall_time_ms <= threshold.max_ms,
                "budget scenario {} exceeded max_ms for threads {}: {} > {}",
                scenario.name,
                threads,
                result.wall_time_ms,
                threshold.max_ms
            );

            measurements.insert(threads, result.wall_time_ms);
        }

        let t1 = *measurements
            .get(&1)
            .unwrap_or_else(|| panic!("scenario {} is missing a t1 baseline", scenario.name));
        let mut previous: Option<(usize, u128)> = None;

        for (threads, wall_time_ms) in measurements {
            if threads != 1 {
                let regression_vs_t1 = regression_pct(t1, wall_time_ms);
                assert!(
                    regression_vs_t1 <= scenario.scaling.max_regression_vs_t1_pct,
                    "scenario {} regressed vs t1 at threads {}: {:.2}% > {:.2}%",
                    scenario.name,
                    threads,
                    regression_vs_t1,
                    scenario.scaling.max_regression_vs_t1_pct
                );
            }

            if let Some((prev_threads, prev_wall_time_ms)) = previous {
                let regression_vs_prev = regression_pct(prev_wall_time_ms, wall_time_ms);
                assert!(
                    regression_vs_prev <= scenario.scaling.max_regression_vs_prev_pct,
                    "scenario {} regressed vs previous thread count {} -> {}: {:.2}% > {:.2}%",
                    scenario.name,
                    prev_threads,
                    threads,
                    regression_vs_prev,
                    scenario.scaling.max_regression_vs_prev_pct
                );
            }

            previous = Some((threads, wall_time_ms));
        }
    }
}

fn load_budget_file() -> BudgetFile {
    let contents = fs::read_to_string(repo_root().join("perf-budgets.yaml"))
        .expect("perf-budgets.yaml should be readable");
    serde_yaml_bw::from_str(&contents).expect("perf-budgets.yaml should parse")
}

fn regression_pct(baseline: u128, current: u128) -> f64 {
    if baseline == 0 || current <= baseline {
        0.0
    } else {
        ((current - baseline) as f64 / baseline as f64) * 100.0
    }
}
