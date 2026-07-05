use std::process;

use strawwu_launcher::cli::{self, Command};
use strawwu_launcher::detect::{detect_from_path, BinaryFormat};
use strawwu_launcher::loader::LaunchRequest;
use strawwu_launcher::registry;
use strawwu_runtime::orchestrator::RuntimeOrchestrator;
use strawwu_runtime::profile::AppProfile;

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
            let mut req = LaunchRequest::new(binary.clone(), format).with_args(app_args);
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

            let app_id = match registry::register_launch(
                &binary,
                format,
                backend.as_deref(),
            ) {
                Ok(id) => id,
                Err(e) => {
                    eprintln!("strawwu: registry register failed: {e}");
                    process::exit(1);
                }
            };

            let mut orch = RuntimeOrchestrator::new();
            let mut profile = AppProfile::default_win32(&app_id);
            if let Some(ref b) = backend {
                profile.execution_backend = b.clone();
            }

            match orch.launch_app(&profile) {
                Ok(pid) => {
                    println!(
                        "strawwu: launched {} (format={}, pid={pid}, backend={}, app_id={app_id})",
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
            match registry::register_install(&installer) {
                Ok(app_id) => {
                    println!(
                        "strawwu: install {} (stub — registered pending app_id={app_id})",
                        installer.display()
                    );
                }
                Err(e) => {
                    eprintln!("strawwu: registry register failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Apps(sub) => match sub {
            cli::AppsSubcommand::List => match registry::list_registered_apps() {
                Ok(apps) if apps.is_empty() => {
                    println!("strawwu: no apps registered");
                }
                Ok(apps) => {
                    for (id, name, kind) in apps {
                        println!("{id}\t{name}\t{kind}");
                    }
                }
                Err(e) => {
                    eprintln!("strawwu: registry list failed: {e}");
                    process::exit(1);
                }
            },
        },
        Command::Profile(_) => {
            println!("strawwu: profile (stub)");
        }
        Command::Repair { app_id } => {
            println!("strawwu: repair {app_id} (stub)");
        }
        Command::Status => {
            match registry::list_registered_apps() {
                Ok(apps) => {
                    println!(
                        "strawwu: status — runtime idle, {} app(s) registered",
                        apps.len()
                    );
                }
                Err(e) => {
                    eprintln!("strawwu: status failed: {e}");
                    process::exit(1);
                }
            }
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
    status
    version
    help

REGISTRY:
    run/install register apps in /var/lib/strawwu/app-registry.json
    (override with STRAWWU_APP_REGISTRY)
"
    );
}
