//! CLI: emit POST-W7 substantive anti-cheat evidence JSON to stdout.
use std::env;

use strawwu_anticheat::substantive::{generate_substantive_report, report_to_json};

fn main() {
    let version = env::args()
        .nth(1)
        .or_else(|| env::var("STRAWWU_VERSION").ok())
        .unwrap_or_else(|| "0.7.0.5".into());

    let report = generate_substantive_report(&version);
    println!("{}", report_to_json(&report));
}
