use std::env;
use std::io;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use greentic_perf_harness::runtime::{DirectLineClient, DirectLineClientOptions, LatencySummary};
use serde::Serialize;

#[derive(Debug, Clone)]
struct Config {
    base_url: String,
    tenant: String,
    threads: usize,
    messages_per_thread: usize,
    poll_timeout_ms: u64,
    client_timeout_ms: u64,
    accept_invalid_certs: bool,
    label: String,
}

#[derive(Debug, Serialize)]
struct RunReport {
    label: String,
    base_url: String,
    tenant: String,
    threads: usize,
    messages_per_thread: usize,
    total_requests: usize,
    successful_requests: usize,
    failed_requests: usize,
    elapsed_ms: u128,
    throughput_msgs_per_sec: f64,
    conversation_create_ms: LatencySummary,
    roundtrip_reply_ms: LatencySummary,
}

#[derive(Debug)]
struct WorkerStats {
    created_ms: u128,
    reply_ms: Vec<u128>,
    success: usize,
    failure: usize,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = parse_args(env::args().skip(1).collect())?;
    if config.threads == 0 {
        return Err("threads must be >= 1".to_owned());
    }
    if config.messages_per_thread == 0 {
        return Err("messages-per-thread must be >= 1".to_owned());
    }

    let options = DirectLineClientOptions {
        timeout: Duration::from_millis(config.client_timeout_ms),
        accept_invalid_certs: config.accept_invalid_certs,
    };
    let client = DirectLineClient::with_options(&config.base_url, &config.tenant, options)
        .map_err(|error| format!("failed to build directline client: {error}"))?;
    let poll_timeout = Duration::from_millis(config.poll_timeout_ms);

    let total_requests = config
        .threads
        .checked_mul(config.messages_per_thread)
        .ok_or_else(|| "total request count overflowed usize".to_owned())?;
    let (tx, rx) = mpsc::channel::<Result<WorkerStats, String>>();
    let started = Instant::now();

    thread::scope(|scope| {
        for worker in 0..config.threads {
            let tx = tx.clone();
            let worker_client = client.clone();
            let label = config.label.clone();
            scope.spawn(move || {
                let result = run_worker(
                    &worker_client,
                    poll_timeout,
                    worker,
                    config.messages_per_thread,
                    &label,
                );
                let _ = tx.send(result);
            });
        }
    });
    drop(tx);

    let elapsed = started.elapsed();
    let mut create_samples = Vec::with_capacity(config.threads);
    let mut reply_samples = Vec::with_capacity(total_requests);
    let mut successful_requests = 0usize;
    let mut failed_requests = 0usize;

    for _ in 0..config.threads {
        let worker_result = rx
            .recv()
            .map_err(|error| format!("failed collecting worker stats: {error}"))?;
        match worker_result {
            Ok(stats) => {
                create_samples.push(stats.created_ms);
                successful_requests = successful_requests.saturating_add(stats.success);
                failed_requests = failed_requests.saturating_add(stats.failure);
                reply_samples.extend(stats.reply_ms);
            }
            Err(error) => return Err(error),
        }
    }

    let throughput_msgs_per_sec = if elapsed.is_zero() {
        0.0
    } else {
        successful_requests as f64 / elapsed.as_secs_f64()
    };

    let report = RunReport {
        label: config.label,
        base_url: config.base_url,
        tenant: config.tenant,
        threads: config.threads,
        messages_per_thread: config.messages_per_thread,
        total_requests,
        successful_requests,
        failed_requests,
        elapsed_ms: elapsed.as_millis(),
        throughput_msgs_per_sec,
        conversation_create_ms: LatencySummary::from_samples(&create_samples),
        roundtrip_reply_ms: LatencySummary::from_samples(&reply_samples),
    };

    let json = serde_json::to_string_pretty(&report)
        .map_err(|error| format!("failed to serialize report: {error}"))?;
    println!("{json}");
    Ok(())
}

fn run_worker(
    client: &DirectLineClient,
    poll_timeout: Duration,
    worker_id: usize,
    messages_per_thread: usize,
    label: &str,
) -> Result<WorkerStats, String> {
    let created_at = Instant::now();
    let conversation = client
        .create_conversation()
        .map_err(|error| format!("worker {worker_id}: conversation creation failed: {error}"))?;
    let created_ms = created_at.elapsed().as_millis();

    let mut success = 0usize;
    let mut failure = 0usize;
    let mut reply_ms = Vec::with_capacity(messages_per_thread);

    for sequence in 0..messages_per_thread {
        let text = format!("perf:{label}:w{worker_id}:m{sequence}");
        let roundtrip_started = Instant::now();
        match send_and_wait_reply(client, &conversation, &text, poll_timeout) {
            Ok(()) => {
                success = success.saturating_add(1);
                reply_ms.push(roundtrip_started.elapsed().as_millis());
            }
            Err(error) => {
                failure = failure.saturating_add(1);
                eprintln!("worker {worker_id}: request {sequence} failed: {error}");
            }
        }
    }

    Ok(WorkerStats {
        created_ms,
        reply_ms,
        success,
        failure,
    })
}

fn send_and_wait_reply(
    client: &DirectLineClient,
    conversation: &greentic_perf_harness::runtime::DirectLineConversation,
    text: &str,
    poll_timeout: Duration,
) -> io::Result<()> {
    client.send_message(conversation, text)?;
    let _ = client.poll_for_reply(conversation, text, poll_timeout)?;
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    let mut config = Config {
        base_url: "http://127.0.0.1:8080/v1/messaging/webchat/default".to_owned(),
        tenant: "default".to_owned(),
        threads: 1,
        messages_per_thread: 10,
        poll_timeout_ms: 10_000,
        client_timeout_ms: 10_000,
        accept_invalid_certs: false,
        label: "measure".to_owned(),
    };

    let mut index = 0usize;
    while index < args.len() {
        let key = &args[index];
        match key.as_str() {
            "--base-url" => {
                index += 1;
                config.base_url = args
                    .get(index)
                    .ok_or_else(|| "missing value for --base-url".to_owned())?
                    .to_owned();
            }
            "--tenant" => {
                index += 1;
                config.tenant = args
                    .get(index)
                    .ok_or_else(|| "missing value for --tenant".to_owned())?
                    .to_owned();
            }
            "--threads" => {
                index += 1;
                config.threads = parse_usize(args.get(index), "--threads")?;
            }
            "--messages-per-thread" => {
                index += 1;
                config.messages_per_thread = parse_usize(args.get(index), "--messages-per-thread")?;
            }
            "--poll-timeout-ms" => {
                index += 1;
                config.poll_timeout_ms = parse_u64(args.get(index), "--poll-timeout-ms")?;
            }
            "--client-timeout-ms" => {
                index += 1;
                config.client_timeout_ms = parse_u64(args.get(index), "--client-timeout-ms")?;
            }
            "--label" => {
                index += 1;
                config.label = args
                    .get(index)
                    .ok_or_else(|| "missing value for --label".to_owned())?
                    .to_owned();
            }
            "--accept-invalid-certs" => {
                config.accept_invalid_certs = true;
            }
            "--help" | "-h" => return Err(usage()),
            other => return Err(format!("unknown argument: {other}\n{}", usage())),
        }
        index += 1;
    }

    Ok(config)
}

fn parse_usize(value: Option<&String>, name: &str) -> Result<usize, String> {
    value
        .ok_or_else(|| format!("missing value for {name}"))?
        .parse::<usize>()
        .map_err(|error| format!("invalid value for {name}: {error}"))
}

fn parse_u64(value: Option<&String>, name: &str) -> Result<u64, String> {
    value
        .ok_or_else(|| format!("missing value for {name}"))?
        .parse::<u64>()
        .map_err(|error| format!("invalid value for {name}: {error}"))
}

fn usage() -> String {
    "usage: cargo run -p greentic-perf-harness --example runtime_webchat_load -- [--base-url URL] [--tenant TENANT] [--threads N] [--messages-per-thread N] [--poll-timeout-ms MS] [--client-timeout-ms MS] [--accept-invalid-certs] [--label TEXT]".to_owned()
}
