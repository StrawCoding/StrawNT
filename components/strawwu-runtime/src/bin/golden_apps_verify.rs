//! CLI: emit POST-Q8 golden apps launch evidence JSON to stdout.
use std::env;
use std::fs;
use std::path::PathBuf;

use strawwu_runtime::golden_apps::{
    default_manifest, generate_golden_apps_report, load_manifest_from_json, report_to_json,
};

fn main() {
    let version = env::args()
        .nth(1)
        .or_else(|| env::var("STRAWWU_VERSION").ok())
        .unwrap_or_else(|| "0.7.0.8".into());

    let manifest_path = env::args().nth(2).map(PathBuf::from).unwrap_or_else(|| {
        PathBuf::from(env::var("STRAWWU_REPO_ROOT").unwrap_or_else(|_| ".".into()))
            .join("components/tests/wincompat/golden-apps.json")
    });

    let manifest = if manifest_path.is_file() {
        let json = fs::read_to_string(&manifest_path).unwrap_or_else(|e| {
            eprintln!("WARN: cannot read {}: {e}; using embedded manifest", manifest_path.display());
            String::new()
        });
        load_manifest_from_json(&json).unwrap_or_else(|e| {
            eprintln!("WARN: {e}; using embedded manifest");
            default_manifest()
        })
    } else {
        default_manifest()
    };

    let report = generate_golden_apps_report(&version, &manifest);
    println!("{}", report_to_json(&report));
}
