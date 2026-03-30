use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use tempfile::TempDir;

pub struct TempWorkspace {
    temp_dir: TempDir,
    working_directory: PathBuf,
}

impl TempWorkspace {
    pub fn from_fixture(scenario_name: &str, fixture: &Path) -> io::Result<Self> {
        let fixture_name = fixture.file_name().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "fixture path must end with a directory or file name",
            )
        })?;
        let safe_scenario_name = scenario_name
            .chars()
            .map(|ch| {
                if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                    ch
                } else {
                    '-'
                }
            })
            .collect::<String>();
        let temp_dir = tempfile::Builder::new()
            .prefix(&format!("greentic-perf-{safe_scenario_name}-"))
            .tempdir()?;
        let working_directory = temp_dir.path().join(fixture_name);

        if fixture.is_dir() {
            copy_dir_recursive(fixture, &working_directory)?;
        } else {
            fs::create_dir_all(temp_dir.path())?;
            fs::copy(fixture, &working_directory)?;
        }

        Ok(Self {
            temp_dir,
            working_directory,
        })
    }

    pub fn path(&self) -> &Path {
        &self.working_directory
    }

    pub fn temp_dir_path(&self) -> &Path {
        self.temp_dir.path()
    }
}

fn copy_dir_recursive(source: &Path, destination: &Path) -> io::Result<()> {
    fs::create_dir_all(destination)?;

    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let target_path = destination.join(entry.file_name());

        if file_type.is_dir() {
            copy_dir_recursive(&entry.path(), &target_path)?;
        } else if file_type.is_file() {
            fs::copy(entry.path(), &target_path)?;
        }
    }

    Ok(())
}
