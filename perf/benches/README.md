# Perf Benches

This directory contains Criterion benchmark entrypoints for CLI-style journeys executed through the shared scenario runner.

Current benchmark:

- `cli_bench.rs`: benchmarks smoke-sized command flows across multiple thread counts.

Local usage examples:

```bash
cargo bench -p greentic-perf-harness --bench cli_bench
cargo bench -p greentic-perf-harness --bench cli_bench -- --save-baseline local
cargo bench -p greentic-perf-harness --bench cli_bench -- --baseline local
```

Benchmark output is written under `target/criterion/`.
