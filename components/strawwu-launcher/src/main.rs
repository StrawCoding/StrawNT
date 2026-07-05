use std::process;

use strawwu_launcher::cli::{self, Command};
use strawwu_launcher::desktop;
use strawwu_launcher::detect::{detect_from_path, BinaryFormat};
use strawwu_launcher::loader::LaunchRequest;
use strawwu_launcher::log;
use strawwu_launcher::pe_loader;
use strawwu_launcher::registry::{self, derive_app_name};
use strawwu_runtime::executor::ExecState;
use strawwu_runtime::orchestrator::RuntimeOrchestrator;
use strawwu_runtime::profile::AppProfile;
use strawwu_runtime::{execute_pe, maybe_run_gui_smoke};

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

            let app_name = derive_app_name(&binary);
            let desktop_path = desktop::write_launcher_desktop(
                &registry::derive_app_id(&binary),
                &binary,
                Some(&app_name),
            );

            let desktop_entry = match desktop_path {
                Ok(path) => Some(path.to_string_lossy().into_owned()),
                Err(e) => {
                    eprintln!("strawwu: desktop entry skipped: {e}");
                    None
                }
            };

            let app_id = match registry::register_launch(
                &binary,
                format,
                backend.as_deref(),
                desktop_entry.clone(),
            ) {
                Ok(id) => id,
                Err(e) => {
                    eprintln!("strawwu: registry register failed: {e}");
                    process::exit(1);
                }
            };

            let pe_data = match pe_loader::load_pe_bytes(&binary, format) {
                Ok(data) => data,
                Err(e) => {
                    eprintln!("strawwu: PE load failed: {e}");
                    process::exit(1);
                }
            };

            let mut orch = RuntimeOrchestrator::new();
            let mut profile = AppProfile::default_win32(&app_id);
            if let Some(ref b) = backend {
                profile.execution_backend = b.clone();
            }

            let exec = execute_pe(&mut orch, &profile, &pe_data);
            if exec.state != ExecState::Running {
                eprintln!(
                    "strawwu: launch failed: {}",
                    exec.error.unwrap_or_else(|| "unknown error".into())
                );
                process::exit(1);
            }

            let gui = match maybe_run_gui_smoke(&pe_data, &app_id, &app_name) {
                Ok(result) => result,
                Err(e) => {
                    eprintln!("strawwu: gui-smoke failed: {e}");
                    process::exit(1);
                }
            };

            if let Some(ref smoke) = gui {
                let _ = log::append_event("gui_smoke", smoke);
                println!(
                    "strawwu: launched {} (format={}, pid={}, backend={}, app_id={}, gui-smoke=PASS hwnd={} compositor={} visible={})",
                    req.binary_path.display(),
                    req.format,
                    exec.pid,
                    profile.execution_backend,
                    app_id,
                    smoke.hwnd,
                    smoke.compositor,
                    smoke.visible,
                );
            } else {
                println!(
                    "strawwu: launched {} (format={}, pid={}, backend={}, app_id={}, gui-smoke=SKIP subsystem=non-gui)",
                    req.binary_path.display(),
                    req.format,
                    exec.pid,
                    profile.execution_backend,
                    app_id,
                );
            }

            if let Some(path) = desktop_entry {
                let _ = log::append_event(
                    "desktop_entry",
                    &serde_json::json!({
                        "app_id": app_id,
                        "path": path,
                    }),
                );
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
                    let sessions = RuntimeOrchestrator::new().session_count();
                    println!(
                        "strawwu: status — runtime idle, {} session(s), {} app(s) registered",
                        sessions,
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

GUI SMOKE (W5-W4):
    PE GUI apps create Win32 HWND + Wayland present bridge (mutter contract)
    Desktop entry written to ~/.local/share/applications (STRAWWU_DESKTOP_DIR)
"
    );
}
