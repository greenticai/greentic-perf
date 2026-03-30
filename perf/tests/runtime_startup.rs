mod support;

use std::time::Duration;

use greentic_perf_harness::runtime::{RuntimeRequest, start_runtime};

use support::{generated_runtime_bundle_artifact, runtime_fixture};

#[test]
fn starts_runtime_bundle_with_gtc_start() {
    let bundle = runtime_fixture("qa-template-worker");
    let artifact = generated_runtime_bundle_artifact("qa-template-worker");

    assert!(bundle.exists(), "runtime bundle fixture should exist");
    assert!(artifact.exists(), "runtime bundle artifact should exist");

    let request = RuntimeRequest::new(bundle.clone());
    let mut handle = start_runtime(&request).expect("runtime should start");
    std::thread::sleep(Duration::from_millis(500));
    assert!(
        handle.is_running().expect("runtime status"),
        "runtime should still be alive after startup"
    );
}
