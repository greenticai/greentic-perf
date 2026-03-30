use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::scenario::RepoRef;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScenarioPhase {
    pub phase: String,
    pub elapsed_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScenarioCommand {
    pub program: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScenarioResult {
    pub scenario_name: String,
    pub repo_ref: RepoRef,
    pub command: ScenarioCommand,
    pub fixture_path: PathBuf,
    pub working_directory: PathBuf,
    pub threads: usize,
    pub timeout_ms: u64,
    pub wall_time_ms: u128,
    pub exit_code: Option<i32>,
    pub success: bool,
    pub timed_out: bool,
    pub stdout_tail: String,
    pub stderr_tail: String,
    pub last_completed_phase: String,
    pub phases: Vec<ScenarioPhase>,
}

impl ScenarioResult {
    pub fn to_json_pretty(&self) -> serde_json::Result<String> {
        serde_json::to_string_pretty(self)
    }
}
