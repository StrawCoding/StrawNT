use std::process;

use strawwu_launcher::cli::{self, Command};
use strawwu_launcher::detect::{detect_from_path, BinaryFormat};
use strawwu_launcher::loader::LaunchRequest;
use strawwu_runtime::profile::AppProfile;
use strawwu_runtime::orchestrator::RuntimeOrchestrator;

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = match cli::parse_args(&args) {
        Ok(cmd) => cmd,
        Err(e) => {
            eprintln!("strawwu: {e}");
            process::exit(1);
        }
    };

    match cmd {
        Command::Version => {
            println!("strawwu {VERSION}");
        }
        Command::Help => {
            print_help();
        }
        Command::Run {
            binary,
            args: app_args,
            backend,
            bundle,
            ..
        } => {
            let format = detect_from_path(&binary).unwrap_or(BinaryFormat::Unknown);
            let mut req = LaunchRequest::new(binary, format).with_args(app_args);
            if let Some(ref b) = backend {
                req = req.with_backend(b);
            }
            if !bundle.is_empty() {
                req = req.with_bundle(bundle);
            }

            if let Err(e) = req.validate() {
                eprintln!("strawwu: launch validation failed: {e}");
                process::exit(1);
            }

            let mut orch = RuntimeOrchestrator::new();
            let mut profile = AppProfile::default_win32(
                req.binary_path.file_stem().unwrap_or_default().to_string_lossy(),
            );
            if let Some(ref b) = backend {
                profile.execution_backend = b.clone();
            }

            match orch.launch_app(&profile) {
                Ok(pid) => {
                    println!(
                        "strawwu: launched {} (format={}, pid={pid}, backend={})",
                        req.binary_path.display(),
                        req.format,
                        profile.execution_backend
                    );
                }
                Err(e) => {
                    eprintln!("strawwu: launch failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Install { installer } => {
            println!("strawwu: install {} (stub — not yet implemented)", installer.display());
        }
        Command::Apps(_) => {
            println!("strawwu: apps list (stub — no apps installed)");
        }
        Command::Profile(_) => {
            println!("strawwu: profile (stub)");
        }
        Command::Repair { app_id } => {
            println!("strawwu: repair {app_id} (stub)");
        }
        Command::Status => {
            println!("strawwu: status — runtime idle, 0 sessions active");
        }
        Command::Config(_) => {
            println!("strawwu: config (stub)");
        }
    }
}

fn print_help() {
    println!(
        "strawwu {VERSION} — StrawWU application launcher

USAGE:
    strawwu <COMMAND> [OPTIONS]

COMMANDS:
    run <binary> [--backend native|container|microvm] [--bundle a,b,c]
    install <installer.exe>
    apps list
    profile inspect|export <app-id>
    repair <app-id>
    version
    help
"
    );
}
