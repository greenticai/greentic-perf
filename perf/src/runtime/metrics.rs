use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RuntimeMetrics {
    pub scenario: String,
    pub bundle: String,
    pub concurrency: usize,
    pub turns_per_conversation: usize,
    pub startup_ms: u128,
    pub conversation_create_ms: LatencySummary,
    pub reply_ms: LatencySummary,
    pub throughput_msgs_per_sec: f64,
    pub error_rate: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LatencySummary {
    pub p50: u128,
    pub p95: u128,
    pub p99: u128,
}

impl LatencySummary {
    pub fn from_samples(samples: &[u128]) -> Self {
        if samples.is_empty() {
            return Self {
                p50: 0,
                p95: 0,
                p99: 0,
            };
        }

        let mut sorted = samples.to_vec();
        sorted.sort_unstable();

        Self {
            p50: percentile(&sorted, 50),
            p95: percentile(&sorted, 95),
            p99: percentile(&sorted, 99),
        }
    }
}

fn percentile(sorted: &[u128], rank: usize) -> u128 {
    let last_index = sorted.len().saturating_sub(1);
    let index = last_index.saturating_mul(rank) / 100;
    sorted[index]
}
