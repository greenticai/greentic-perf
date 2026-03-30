use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tempfile::NamedTempFile;

use crate::result::{ScenarioCommand, ScenarioPhase, ScenarioResult};
use crate::temp_workspace::TempWorkspace;
use crate::threads::{THREAD_ENV_VAR, normalize_thread_count};

const DEFAULT_PROGRAM: &str = "gtc";
const TAIL_LINE_LIMIT: usize = 40;
const POLL_INTERVAL_MS: u64 = 25;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "value")]
pub enum RepoRef {
    CurrentCheckout,
    GitRef(String),
    Path(PathBuf),
}

pub fn run_scenario(
    scenario_name: &str,
    repo_ref: RepoRef,
    args: &[&str],
    fixture: &Path,
    threads: usize,
    timeout: Duration,
) -> io::Result<ScenarioResult> {
    let started_at = Instant::now();
    let mut phases = Vec::new();
    let normalized_threads = normalize_thread_count(threads)?;
    let fixture_path = fixture.canonicalize()?;
    record_phase(&mut phases, "checkout/setup", started_at);
    let workspace = TempWorkspace::from_fixture(scenario_name, &fixture_path)?;
    record_phase(&mut phases, "fixture_prep", started_at);
    let stdout_file = NamedTempFile::new()?;
    let stderr_file = NamedTempFile::new()?;
    let stdout_path = stdout_file.path().to_path_buf();
    let stderr_path = stderr_file.path().to_path_buf();
    let resolved_program = resolve_program(&repo_ref);

    let mut command = Command::new(&resolved_program);
    command
        .args(args)
        .current_dir(workspace.path())
        .env(THREAD_ENV_VAR, normalized_threads.to_string())
        .env("GREENTIC_PERF_SCENARIO_NAME", scenario_name)
        .env("GREENTIC_PERF_FIXTURE_PATH", &fixture_path)
        .env("GREENTIC_PERF_REPO_REF", repo_ref_label(&repo_ref))
        .stdout(Stdio::from(stdout_file.reopen()?))
        .stderr(Stdio::from(stderr_file.reopen()?));

    let mut child = command.spawn()?;
    record_phase(&mut phases, "command_start", started_at);
    let completion = wait_for_child(&mut child, timeout, started_at, &mut phases)?;
    let wall_time = started_at.elapsed();
    let stdout_tail = read_tail(&stdout_path)?;
    let stderr_tail = read_tail(&stderr_path)?;
    let last_completed_phase = phases
        .last()
        .map(|phase| phase.phase.clone())
        .unwrap_or_else(|| "checkout/setup".to_owned());

    Ok(ScenarioResult {
        scenario_name: scenario_name.to_owned(),
        repo_ref,
        command: ScenarioCommand {
            program: resolved_program.to_string_lossy().into_owned(),
            args: args.iter().map(|arg| (*arg).to_owned()).collect(),
        },
        fixture_path,
        working_directory: workspace.path().to_path_buf(),
        threads: normalized_threads,
        timeout_ms: timeout.as_millis() as u64,
        wall_time_ms: wall_time.as_millis(),
        exit_code: completion.status.and_then(|status| status.code()),
        success: completion
            .status
            .map(|status| status.success())
            .unwrap_or(false)
            && !completion.timed_out,
        timed_out: completion.timed_out,
        stdout_tail,
        stderr_tail,
        last_completed_phase,
        phases,
    })
}

struct Completion {
    status: Option<ExitStatus>,
    timed_out: bool,
}

fn wait_for_child(
    child: &mut std::process::Child,
    timeout: Duration,
    started_at: Instant,
    phases: &mut Vec<ScenarioPhase>,
) -> io::Result<Completion> {
    let deadline = Instant::now() + timeout;

    loop {
        if let Some(status) = child.try_wait()? {
            record_phase(phases, "command_end", started_at);
            return Ok(Completion {
                status: Some(status),
                timed_out: false,
            });
        }

        if Instant::now() >= deadline {
            child.kill()?;
            let _ = child.wait();
            record_phase(phases, "timeout", started_at);
            return Ok(Completion {
                status: None,
                timed_out: true,
            });
        }

        thread::sleep(Duration::from_millis(POLL_INTERVAL_MS));
    }
}

fn record_phase(phases: &mut Vec<ScenarioPhase>, phase: &str, started_at: Instant) {
    phases.push(ScenarioPhase {
        phase: phase.to_owned(),
        elapsed_ms: started_at.elapsed().as_millis(),
    });
}

fn resolve_program(repo_ref: &RepoRef) -> OsString {
    match repo_ref {
        RepoRef::Path(path) => resolve_named_program(path),
        _ => std::env::var_os("GTC_BIN").unwrap_or_else(|| OsString::from(DEFAULT_PROGRAM)),
    }
}

fn resolve_named_program(path: &Path) -> OsString {
    if path.is_absolute() || path.components().count() > 1 {
        return path.as_os_str().to_owned();
    }

    std::env::var_os("PATH")
        .and_then(|path_env| {
            std::env::split_paths(&path_env)
                .map(|entry| entry.join(path))
                .find(|candidate| candidate.is_file())
        })
        .unwrap_or_else(|| path.to_path_buf())
        .into_os_string()
}

fn repo_ref_label(repo_ref: &RepoRef) -> String {
    match repo_ref {
        RepoRef::CurrentCheckout => "current-checkout".to_owned(),
        RepoRef::GitRef(reference) => format!("git:{reference}"),
        RepoRef::Path(path) => format!("path:{}", path.display()),
    }
}

fn read_tail(path: &Path) -> io::Result<String> {
    let contents = fs::read_to_string(path)?;
    let lines: Vec<&str> = contents.lines().collect();
    let start = lines.len().saturating_sub(TAIL_LINE_LIMIT);
    Ok(lines[start..].join("\n"))
}
