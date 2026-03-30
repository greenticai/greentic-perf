use std::fs;
use std::path::{Path, PathBuf};

use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct EstimatesFile {
    mean: Estimate,
}

#[derive(Debug, Deserialize)]
struct Estimate {
    point_estimate: f64,
}

#[derive(Debug)]
struct BenchmarkSummary {
    scenario: String,
    thread_label: String,
    mean_ns: f64,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let criterion_root = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("target/criterion"));
    let output_path = args.next().map(PathBuf::from);

    let mut summaries = Vec::new();
    collect_summaries(&criterion_root, &mut summaries)?;
    summaries.sort_by(|left, right| left.mean_ns.total_cmp(&right.mean_ns));

    let markdown = render_markdown(&summaries);
    if let Some(path) = output_path {
        fs::write(&path, markdown).map_err(|error| format!("failed to write summary: {error}"))?;
    } else {
        println!("{markdown}");
    }

    Ok(())
}

fn collect_summaries(root: &Path, out: &mut Vec<BenchmarkSummary>) -> Result<(), String> {
    if !root.exists() {
        return Err(format!("criterion directory not found: {}", root.display()));
    }

    for entry in
        fs::read_dir(root).map_err(|error| format!("failed to read {}: {error}", root.display()))?
    {
        let entry =
            entry.map_err(|error| format!("failed to iterate {}: {error}", root.display()))?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let scenario_name = entry.file_name().to_string_lossy().replace('_', "/");
        if scenario_name == "report" {
            continue;
        }

        for thread_entry in fs::read_dir(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?
        {
            let thread_entry = thread_entry
                .map_err(|error| format!("failed to iterate {}: {error}", path.display()))?;
            let thread_path = thread_entry.path();
            if !thread_path.is_dir() {
                continue;
            }

            let thread_label = thread_entry.file_name().to_string_lossy().to_string();
            if thread_label == "report" {
                continue;
            }

            let estimates_path = thread_path.join("new/estimates.json");
            if !estimates_path.exists() {
                continue;
            }

            let estimates_contents = fs::read_to_string(&estimates_path)
                .map_err(|error| format!("failed to read {}: {error}", estimates_path.display()))?;
            let estimates: EstimatesFile =
                serde_json::from_str(&estimates_contents).map_err(|error| {
                    format!("failed to parse {}: {error}", estimates_path.display())
                })?;

            out.push(BenchmarkSummary {
                scenario: scenario_name.clone(),
                thread_label,
                mean_ns: estimates.mean.point_estimate,
            });
        }
    }

    Ok(())
}

fn render_markdown(summaries: &[BenchmarkSummary]) -> String {
    if summaries.is_empty() {
        return "# Nightly Perf Summary\n\nNo Criterion estimates were found.\n".to_owned();
    }

    let fastest = &summaries[0];
    let slowest = &summaries[summaries.len() - 1];
    let mut markdown = String::from("# Nightly Perf Summary\n\n");
    markdown.push_str(&format!(
        "- Fastest: `{}` `{}` at {:.3} ms\n",
        fastest.scenario,
        fastest.thread_label,
        fastest.mean_ns / 1_000_000.0
    ));
    markdown.push_str(&format!(
        "- Slowest: `{}` `{}` at {:.3} ms\n\n",
        slowest.scenario,
        slowest.thread_label,
        slowest.mean_ns / 1_000_000.0
    ));
    markdown.push_str("| Scenario | Threads | Mean |\n");
    markdown.push_str("| --- | --- | --- |\n");
    for summary in summaries {
        markdown.push_str(&format!(
            "| `{}` | `{}` | {:.3} ms |\n",
            summary.scenario,
            summary.thread_label,
            summary.mean_ns / 1_000_000.0
        ));
    }
    markdown
}
