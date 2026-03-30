use std::env;
use std::path::PathBuf;
use std::process;
use std::time::Duration;

use greentic_perf_harness::{RepoRef, run_scenario};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let scenario_name = args
        .next()
        .ok_or_else(|| usage("missing <scenario-name>"))?;
    let fixture = PathBuf::from(args.next().ok_or_else(|| usage("missing <fixture-path>"))?);
    let threads = args
        .next()
        .ok_or_else(|| usage("missing <threads>"))?
        .parse::<usize>()
        .map_err(|error| format!("invalid <threads>: {error}"))?;
    let timeout_ms = args
        .next()
        .ok_or_else(|| usage("missing <timeout-ms>"))?
        .parse::<u64>()
        .map_err(|error| format!("invalid <timeout-ms>: {error}"))?;

    let scenario_args: Vec<String> = args.collect();
    if scenario_args.is_empty() {
        return Err(usage("missing command arguments after <timeout-ms>"));
    }

    let binary = env::var_os("GREENTIC_PERF_BIN")
        .or_else(|| env::var_os("GTC_BIN"))
        .unwrap_or_else(|| "gtc".into());
    let repo_ref = RepoRef::Path(PathBuf::from(binary));

    let arg_refs: Vec<&str> = scenario_args.iter().map(String::as_str).collect();
    let result = run_scenario(
        &scenario_name,
        repo_ref,
        &arg_refs,
        &fixture,
        threads,
        Duration::from_millis(timeout_ms),
    )
    .map_err(|error| format!("scenario execution failed: {error}"))?;

    let json = result
        .to_json_pretty()
        .map_err(|error| format!("failed to serialize result: {error}"))?;
    println!("{json}");

    if result.success {
        Ok(())
    } else {
        Err(format!(
            "scenario '{}' failed: success={}, timed_out={}, exit_code={:?}",
            result.scenario_name, result.success, result.timed_out, result.exit_code
        ))
    }
}

fn usage(message: &str) -> String {
    format!(
        "{message}\nusage: cargo run -p greentic-perf-harness --example scenario_json -- <scenario-name> <fixture-path> <threads> <timeout-ms> <command> [args...]"
    )
}
