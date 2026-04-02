mod support;

use std::time::Duration;

use greentic_perf_harness::runtime::{
    DirectLineClient, RuntimeRequest, start_runtime, wait_for_runtime_readiness,
};

use support::runtime_fixture;

#[test]
#[ignore = "requires a runtime bundle with an installed messaging-webchat provider pack"]
fn runtime_single_turn_over_directline() {
    let bundle = runtime_fixture("qa-template-worker");
    let mut handle = start_runtime(&RuntimeRequest::new(bundle)).expect("runtime should start");
    let endpoints =
        wait_for_runtime_readiness(&mut handle, Duration::from_secs(10)).expect("runtime ready");

    let client = DirectLineClient::new(endpoints.directline_base_url(), handle.tenant.clone())
        .expect("client");
    let conversation = client
        .create_conversation()
        .expect("conversation should be created");
    client
        .send_message(&conversation, "42")
        .expect("message should be sent");
    let reply = client
        .poll_for_reply(&conversation, "42", Duration::from_secs(10))
        .expect("reply should arrive");
    assert!(
        reply.text.contains("42"),
        "reply should echo the probe number"
    );
}
