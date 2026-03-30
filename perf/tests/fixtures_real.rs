#[cfg(unix)]
mod support;

#[cfg(unix)]
use support::{
    ensure_generated_fixtures, generated_bundle_fixture, generated_pack_fixture, repo_root,
};

#[cfg(unix)]
#[test]
fn generated_real_fixtures_exist_for_all_tiers() {
    ensure_generated_fixtures();

    for tier in ["smoke", "medium", "heavy"] {
        assert!(
            generated_pack_fixture(tier).join("pack.yaml").exists(),
            "missing generated pack fixture for {tier}"
        );
        assert!(
            generated_bundle_fixture(tier).join("bundle.yaml").exists(),
            "missing generated bundle fixture for {tier}"
        );
        assert!(
            repo_root()
                .join("fixtures-gen")
                .join(tier)
                .join("artifacts")
                .join(format!("perf-{tier}-bundle.gtbundle"))
                .exists(),
            "missing generated bundle artifact for {tier}"
        );
    }
}
