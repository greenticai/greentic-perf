use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use criterion::{BenchmarkId, Criterion, Throughput, criterion_group, criterion_main};
use greentic_perf_harness::{RepoRef, run_scenario};

#[cfg(unix)]
struct BenchCase {
    scenario: &'static str,
    binary: &'static str,
    fixture: PathBuf,
    args: &'static [&'static str],
    thread_counts: Vec<usize>,
}

#[cfg(unix)]
fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("perf crate should live under the repo root")
        .to_path_buf()
}

#[cfg(unix)]
fn smoke_fixture() -> PathBuf {
    ensure_generated_fixtures();
    repo_root().join("fixtures-gen/smoke/packs/perf-smoke-pack")
}

#[cfg(unix)]
fn smoke_bundle_fixture() -> PathBuf {
    ensure_generated_fixtures();
    repo_root().join("fixtures-gen/smoke/bundles/perf-smoke-bundle")
}

#[cfg(unix)]
fn smoke_tier_fixture() -> PathBuf {
    ensure_generated_fixtures();
    repo_root().join("fixtures-gen/smoke")
}

#[cfg(unix)]
fn medium_bundle_fixture() -> PathBuf {
    ensure_generated_fixtures();
    repo_root().join("fixtures-gen/medium/bundles/perf-medium-bundle")
}

#[cfg(unix)]
fn heavy_bundle_fixture() -> PathBuf {
    ensure_generated_fixtures();
    repo_root().join("fixtures-gen/heavy/bundles/perf-heavy-bundle")
}

#[cfg(unix)]
fn ensure_generated_fixtures() {
    let status = Command::new("bash")
        .arg("scripts/check_fixtures.sh")
        .current_dir(repo_root())
        .status()
        .expect("fixture generation script should run");
    assert!(status.success(), "fixture generation should succeed");
}

#[cfg(unix)]
fn benchmark_repo_ref(binary: &str) -> RepoRef {
    let status = Command::new(binary)
        .arg("--version")
        .status()
        .unwrap_or_else(|error| panic!("failed to execute {binary} --version: {error}"));
    assert!(status.success(), "{binary} --version should succeed");
    RepoRef::Path(PathBuf::from(binary))
}

#[cfg(unix)]
fn bench_cli_journeys(criterion: &mut Criterion) {
    let profile = std::env::var("GREENTIC_BENCH_PROFILE").unwrap_or_else(|_| "pr".to_owned());
    let cases: Vec<BenchCase> = match profile.as_str() {
        "nightly" => vec![
            BenchCase {
                scenario: "pack_build/smoke",
                binary: "greentic-dev",
                fixture: smoke_fixture(),
                args: &["pack", "build", "--in", "."],
                thread_counts: vec![1, 2, 4, 8, 16],
            },
            BenchCase {
                scenario: "bundle_build/medium",
                binary: "greentic-bundle",
                fixture: medium_bundle_fixture(),
                args: &["build"],
                thread_counts: vec![1, 2, 4, 8, 16],
            },
            BenchCase {
                scenario: "bundle_build/heavy",
                binary: "greentic-bundle",
                fixture: heavy_bundle_fixture(),
                args: &["build"],
                thread_counts: vec![1, 2, 4, 8, 16],
            },
            BenchCase {
                scenario: "bundle_inspect_artifact/smoke",
                binary: "greentic-bundle",
                fixture: smoke_tier_fixture(),
                args: &[
                    "inspect",
                    "--artifact",
                    "artifacts/perf-smoke-bundle.gtbundle",
                    "--json",
                    "--offline",
                ],
                thread_counts: vec![1, 2, 4, 8, 16],
            },
        ],
        _ => vec![
            BenchCase {
                scenario: "pack_build/smoke",
                binary: "greentic-dev",
                fixture: smoke_fixture(),
                args: &["pack", "build", "--in", "."],
                thread_counts: vec![1, 4],
            },
            BenchCase {
                scenario: "bundle_build/smoke",
                binary: "greentic-bundle",
                fixture: smoke_bundle_fixture(),
                args: &["build"],
                thread_counts: vec![1, 8],
            },
            BenchCase {
                scenario: "bundle_inspect_artifact/smoke",
                binary: "greentic-bundle",
                fixture: smoke_tier_fixture(),
                args: &[
                    "inspect",
                    "--artifact",
                    "artifacts/perf-smoke-bundle.gtbundle",
                    "--json",
                    "--offline",
                ],
                thread_counts: vec![1, 8],
            },
        ],
    };

    for case in cases {
        let repo_ref = benchmark_repo_ref(case.binary);
        let mut group = criterion.benchmark_group(case.scenario);
        group.sample_size(10);
        group.measurement_time(Duration::from_secs(2));
        group.warm_up_time(Duration::from_millis(250));
        group.throughput(Throughput::Elements(1));

        for threads in case.thread_counts {
            group.bench_with_input(
                BenchmarkId::from_parameter(format!("t{threads}")),
                &threads,
                |b, &threads| {
                    b.iter(|| {
                        let result = run_scenario(
                            &format!("{}-t{threads}", case.scenario),
                            repo_ref.clone(),
                            case.args,
                            &case.fixture,
                            threads,
                            Duration::from_secs(2),
                        )
                        .expect("benchmark scenario should run");

                        assert!(
                            result.success,
                            "benchmark scenario failed: {} t{threads}",
                            case.scenario
                        );
                    });
                },
            );
        }

        group.finish();
    }
}

#[cfg(not(unix))]
fn bench_cli_journeys(_criterion: &mut Criterion) {}

criterion_group!(cli_benchmarks, bench_cli_journeys);
criterion_main!(cli_benchmarks);
