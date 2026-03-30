use std::io;
use std::net::TcpStream;
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use super::start::{RuntimeHandle, runtime_state_root};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RuntimeEndpointInfo {
    pub tenant: String,
    pub team: String,
    pub public_base_url: Option<String>,
    pub nats_url: Option<String>,
    pub gateway_listen_addr: String,
    pub gateway_port: u16,
}

impl RuntimeEndpointInfo {
    pub fn gateway_base_url(&self) -> String {
        format!("http://{}:{}", self.gateway_listen_addr, self.gateway_port)
    }
}

pub fn wait_for_runtime_readiness(
    handle: &mut RuntimeHandle,
    timeout: Duration,
) -> io::Result<RuntimeEndpointInfo> {
    let started = Instant::now();
    let endpoints_path = runtime_state_root(
        &handle.bundle_ref,
        Some(&handle.state_dir),
        &handle.tenant,
        &handle.team,
    )
    .join("endpoints.json");
    let static_routes_path = handle
        .bundle_ref
        .join("state")
        .join("config")
        .join("platform")
        .join("static-routes.json");

    loop {
        if let Some(endpoints) = load_endpoints(
            &endpoints_path,
            &static_routes_path,
            &handle.tenant,
            &handle.team,
        )? && TcpStream::connect((
            endpoints.gateway_listen_addr.as_str(),
            endpoints.gateway_port,
        ))
        .is_ok()
        {
            return Ok(endpoints);
        }

        if !handle.is_running()? {
            return Err(io::Error::other("runtime exited before becoming ready"));
        }

        if started.elapsed() >= timeout {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!(
                    "runtime did not become ready within {} ms",
                    timeout.as_millis()
                ),
            ));
        }

        thread::sleep(Duration::from_millis(100));
    }
}

#[derive(Debug, Deserialize)]
struct StaticRoutesConfig {
    #[serde(default)]
    public_base_url: Option<String>,
}

fn load_endpoints(
    endpoints_path: &Path,
    static_routes_path: &Path,
    tenant: &str,
    team: &str,
) -> io::Result<Option<RuntimeEndpointInfo>> {
    if endpoints_path.exists() {
        let raw = std::fs::read_to_string(endpoints_path)?;
        let endpoints = serde_json::from_str(&raw).map_err(io::Error::other)?;
        return Ok(Some(endpoints));
    }

    if static_routes_path.exists() {
        let raw = std::fs::read_to_string(static_routes_path)?;
        let config: StaticRoutesConfig = serde_json::from_str(&raw).map_err(io::Error::other)?;
        if let Some(public_base_url) = config.public_base_url
            && let Some((gateway_listen_addr, gateway_port)) = parse_http_base_url(&public_base_url)
        {
            return Ok(Some(RuntimeEndpointInfo {
                tenant: tenant.to_owned(),
                team: team.to_owned(),
                public_base_url: Some(public_base_url),
                nats_url: None,
                gateway_listen_addr,
                gateway_port,
            }));
        }
    }

    Ok(None)
}

fn parse_http_base_url(value: &str) -> Option<(String, u16)> {
    let remainder = value.strip_prefix("http://")?;
    let host_port = remainder.split('/').next()?;
    let (host, port) = host_port.rsplit_once(':')?;
    let port = port.parse().ok()?;
    Some((host.to_owned(), port))
}
