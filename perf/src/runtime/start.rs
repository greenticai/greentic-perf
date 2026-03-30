use std::fs::File;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

#[derive(Debug, Clone)]
pub struct RuntimeRequest {
    pub bundle_ref: PathBuf,
    pub tenant: String,
    pub team: String,
    pub state_dir: Option<PathBuf>,
    pub log_dir: Option<PathBuf>,
}

impl RuntimeRequest {
    pub fn new(bundle_ref: impl Into<PathBuf>) -> Self {
        Self {
            bundle_ref: bundle_ref.into(),
            tenant: "demo".to_owned(),
            team: "default".to_owned(),
            state_dir: None,
            log_dir: None,
        }
    }
}

#[derive(Debug)]
pub struct RuntimeHandle {
    child: Child,
    pub bundle_ref: PathBuf,
    pub tenant: String,
    pub team: String,
    pub state_dir: PathBuf,
    pub log_dir: PathBuf,
}

impl RuntimeHandle {
    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    pub fn is_running(&mut self) -> io::Result<bool> {
        Ok(self.child.try_wait()?.is_none())
    }

    pub fn shutdown(&mut self) -> io::Result<()> {
        if self.child.try_wait()?.is_some() {
            return Ok(());
        }
        self.child.kill()?;
        let _ = self.child.wait()?;
        Ok(())
    }
}

impl Drop for RuntimeHandle {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

pub fn start_runtime(request: &RuntimeRequest) -> io::Result<RuntimeHandle> {
    let state_dir = request
        .state_dir
        .clone()
        .unwrap_or_else(|| request.bundle_ref.join("state"));
    let log_dir = request
        .log_dir
        .clone()
        .unwrap_or_else(|| request.bundle_ref.join("logs"));

    std::fs::create_dir_all(&state_dir)?;
    std::fs::create_dir_all(&log_dir)?;

    let stdout_path = log_dir.join("runtime.stdout.log");
    let stderr_path = log_dir.join("runtime.stderr.log");
    let stdout = File::create(&stdout_path)?;
    let stderr = File::create(&stderr_path)?;

    let mut command = Command::new("gtc");
    command
        .arg("start")
        .arg(&request.bundle_ref)
        .arg("--tenant")
        .arg(&request.tenant)
        .arg("--team")
        .arg(&request.team)
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr));

    let child = command.spawn()?;

    Ok(RuntimeHandle {
        child,
        bundle_ref: request.bundle_ref.clone(),
        tenant: request.tenant.clone(),
        team: request.team.clone(),
        state_dir,
        log_dir,
    })
}

pub fn runtime_state_root(
    bundle_ref: &Path,
    state_dir: Option<&Path>,
    tenant: &str,
    team: &str,
) -> PathBuf {
    state_dir
        .map(PathBuf::from)
        .unwrap_or_else(|| bundle_ref.join("state"))
        .join("runtime")
        .join(format!("{tenant}.{team}"))
}
