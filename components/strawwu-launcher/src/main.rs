use std::path::{Path, PathBuf};
use std::process;

use strawwu_launcher::cli::{self, Command, OpenMode};
use strawwu_launcher::desktop;
use strawwu_launcher::detect::{detect_from_path, BinaryFormat};
use strawwu_launcher::loader::LaunchRequest;
use strawwu_launcher::log;
use strawwu_launcher::open::{self, OpenAction};
use strawwu_launcher::pe_loader;
use strawwu_launcher::registry::{self, derive_app_name};
use strawwu_runtime::executor::ExecState;
use strawwu_runtime::orchestrator::RuntimeOrchestrator;
use strawwu_runtime::profile::AppProfile;
use strawwu_runtime::maybe_run_gui_smoke;

const VERSION: &str = env!("CARGO_PKG_VERSION");

// Restore default SIGPIPE so the CLI is terminated by the signal (like any Unix
// filter) when a downstream reader closes the pipe early — e.g. `strawwu ... |
// grep -q` / `| head`. Rust otherwise ignores SIGPIPE and panics on the failed
// stdout write ("Broken pipe"). Must run before any stdout output.
#[cfg(unix)]
fn reset_sigpipe() {
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
}

#[cfg(not(unix))]
fn reset_sigpipe() {}

fn main() {
    reset_sigpipe();
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
            let install_mode = open::looks_like_installer(&binary);
            if let Err(code) = launch_pe(
                &binary,
                &app_args,
                backend.as_deref(),
                &bundle,
                false,
                install_mode,
            ) {
                process::exit(code);
            }
        }
        Command::Open { path, mode } => {
            let action = match mode {
                OpenMode::Run => OpenAction::Run,
                OpenMode::Install => OpenAction::InstallAndRun,
                OpenMode::Auto => open::decide_open_action(&path),
            };
            let install_mode = matches!(action, OpenAction::InstallAndRun);

            if install_mode {
                match registry::register_install(&path) {
                    Ok(app_id) => {
                        println!(
                            "strawwu: open/install registered pending app_id={app_id} ({})",
                            path.display()
                        );
                    }
                    Err(e) => {
                        eprintln!("strawwu: open install register failed: {e}");
                        process::exit(1);
                    }
                }
            }

            let name = derive_app_name(&path);
            open::notify(
                "StrawWU",
                &format!(
                    "{} {}",
                    if install_mode {
                        "Installing & launching"
                    } else {
                        "Launching"
                    },
                    name
                ),
            );

            if let Err(code) = launch_pe(&path, &[], None, &[], true, install_mode) {
                open::notify("StrawWU", &format!("Failed to open {name}"));
                process::exit(code);
            }
            open::notify(
                "StrawWU",
                &format!("{name} ready — also available from the app menu"),
            );
        }
        Command::Install { installer } => {
            match registry::register_install(&installer) {
                Ok(app_id) => {
                    let app_name = derive_app_name(&installer);
                    let desktop_path = desktop::write_launcher_desktop(
                        &app_id,
                        &installer,
                        Some(&app_name),
                    );
                    match desktop_path {
                        Ok(path) => {
                            println!(
                                "strawwu: install {} (registered pending app_id={app_id}; desktop={})",
                                installer.display(),
                                path.display()
                            );
                        }
                        Err(e) => {
                            println!(
                                "strawwu: install {} (registered pending app_id={app_id}; desktop skipped: {e})",
                                installer.display()
                            );
                        }
                    }
                    // Run the installer through the native strawwu-nt path.
                    if let Err(code) =
                        launch_pe(&installer, &[], Some("native"), &[], false, true)
                    {
                        open::notify("StrawWU", &format!("Install failed: {app_name}"));
                        process::exit(code);
                    }
                    open::notify(
                        "StrawWU",
                        &format!("{app_name} installed — use the app menu or strawwu open to launch"),
                    );
                }
                Err(e) => {
                    eprintln!("strawwu: registry register failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Integrate => match desktop::install_desktop_integration() {
            Ok(path) => {
                println!(
                    "strawwu: desktop integration installed\n  handler: {}\n  tip: double-click .exe / .msi to install & launch",
                    path.display()
                );
                open::notify(
                    "StrawWU",
                    "Click-to-open enabled for Windows .exe / .msi files",
                );
            }
            Err(e) => {
                eprintln!("strawwu: integrate failed: {e}");
                process::exit(1);
            }
        },
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
        Command::Devices(sub) => match sub {
            cli::DevicesSubcommand::List { json } => {
                use strawwu_cli::devices::{list_devices, ListFormat};
                let format = if json {
                    ListFormat::Json
                } else {
                    ListFormat::Text
                };
                match list_devices(format) {
                    Ok(out) => println!("{out}"),
                    Err(e) => {
                        eprintln!("strawwu: devices list failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Mfp(sub) => match sub {
            cli::MfpSubcommand::Smoke { json } => {
                use strawwu_cli::mfp::{mfp_smoke_passed, run_mfp_smoke_command, MfpFormat};
                let format = if json {
                    MfpFormat::Json
                } else {
                    MfpFormat::Text
                };
                match run_mfp_smoke_command(format) {
                    Ok((out, payload)) => {
                        println!("{out}");
                        if !mfp_smoke_passed(&payload) {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawwu: mfp smoke failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Profile(_) => {
            println!("strawwu: profile (stub)");
        }
        Command::Repair { app_id } => {
            println!("strawwu: repair {app_id} (stub)");
        }
        Command::Status => match registry::list_registered_apps() {
            Ok(apps) => {
                let sessions = RuntimeOrchestrator::new().session_count();
                println!(
                    "strawwu: status — runtime idle, {} session(s), {} app(s) registered",
                    sessions,
                    apps.len()
                );
                println!("strawwu: execution_backend=native (strawwu-nt)");
                println!("strawwu: default backend=native");
            }
            Err(e) => {
                eprintln!("strawwu: status failed: {e}");
                process::exit(1);
            }
        },
        Command::Config(_) => {
            println!("strawwu: config (stub)");
        }
    }
}

/// Resolve execution backend. Default is **native** (self-built strawwu-nt).
fn resolve_backend(requested: Option<&str>) -> String {
    match requested {
        Some(b) if !b.is_empty() => b.to_string(),
        _ => std::env::var("STRAWWU_BACKEND").unwrap_or_else(|_| "native".into()),
    }
}

/// Shared PE launch path used by `run`, `open`, and `install`.
/// Returns Ok(()) or Err(exit_code).
fn launch_pe(
    binary: &Path,
    app_args: &[String],
    backend: Option<&str>,
    bundle: &[PathBuf],
    from_open: bool,
    _install_mode: bool,
) -> Result<(), i32> {
    let format = detect_from_path(binary).unwrap_or(BinaryFormat::Unknown);
    let backend_name = resolve_backend(backend);
    let mut req = LaunchRequest::new(binary.to_path_buf(), format).with_args(app_args.to_vec());
    req = req.with_backend(&backend_name);
    if !bundle.is_empty() {
        req = req.with_bundle(bundle.to_vec());
    }

    if let Err(e) = req.validate() {
        eprintln!("strawwu: launch validation failed: {e}");
        return Err(1);
    }

    let app_name = derive_app_name(binary);
    let desktop_path =
        desktop::write_launcher_desktop(&registry::derive_app_id(binary), binary, Some(&app_name));

    let desktop_entry = match desktop_path {
        Ok(path) => {
            if from_open {
                println!("strawwu: desktop launcher → {}", path.display());
            }
            Some(path.to_string_lossy().into_owned())
        }
        Err(e) => {
            eprintln!("strawwu: desktop entry skipped: {e}");
            None
        }
    };

    let app_id = match registry::register_launch(
        binary,
        format,
        Some(backend_name.as_str()),
        desktop_entry.clone(),
    ) {
        Ok(id) => id,
        Err(e) => {
            eprintln!("strawwu: registry register failed: {e}");
            return Err(1);
        }
    };

    launch_via_native(
        binary,
        format,
        &backend_name,
        &app_id,
        &app_name,
        &req,
        from_open,
        desktop_entry,
    )
}

fn launch_via_native(
    binary: &Path,
    format: BinaryFormat,
    backend_name: &str,
    app_id: &str,
    app_name: &str,
    req: &LaunchRequest,
    from_open: bool,
    desktop_entry: Option<String>,
) -> Result<(), i32> {
    let pe_data = match pe_loader::load_pe_bytes(binary, format, pe_loader::smoke_mode()) {
        Ok(data) => data,
        Err(e) => {
            eprintln!("strawwu: PE load failed: {e}");
            return Err(1);
        }
    };

    let mut orch = RuntimeOrchestrator::new();
    let mut profile = AppProfile::default_win32(app_id);
    profile.execution_backend = backend_name.to_string();

    let side_dir = std::env::var_os("STRAWWU_PE_SIDE_EFFECT_DIR").map(std::path::PathBuf::from);
    let exec = strawwu_runtime::execute_pe_with_side_effect_dir(
        &mut orch,
        &profile,
        &pe_data,
        side_dir,
    );
    if exec.state != ExecState::Running {
        eprintln!(
            "strawwu: launch failed: {}",
            exec.error.unwrap_or_else(|| "unknown error".into())
        );
        return Err(1);
    }

    let mode = exec.mode.as_str();
    if mode == "simulated" && std::env::var_os("STRAWWU_REQUIRE_REAL_EXEC").is_some() {
        eprintln!("strawwu: real CPU execution required but mode=simulated");
        return Err(1);
    }

    let gui = match maybe_run_gui_smoke(&pe_data, app_id, app_name) {
        Ok(result) => result,
        Err(e) => {
            eprintln!("strawwu: gui-smoke failed: {e}");
            return Err(1);
        }
    };

    let cpu_gui = exec.side_effects.as_ref().and_then(|se| se.gui.as_ref());
    if let Some(g) = cpu_gui {
        let _ = log::append_event("gui_cpu", g);
        println!(
            "strawwu: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=PASS hwnd={} compositor={} visible={} closed={} frames={} cpu-user32=1)",
            req.binary_path.display(),
            req.format,
            exec.pid,
            profile.execution_backend,
            app_id,
            mode,
            g.hwnd.unwrap_or(0),
            g.compositor_backend,
            g.visible || !g.closed,
            g.closed,
            g.compositor_frames,
        );
    } else if let Some(ref smoke) = gui {
        let _ = log::append_event("gui_smoke", smoke);
        println!(
            "strawwu: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=PASS hwnd={} compositor={} visible={})",
            req.binary_path.display(),
            req.format,
            exec.pid,
            profile.execution_backend,
            app_id,
            mode,
            smoke.hwnd,
            smoke.compositor,
            smoke.visible,
        );
    } else {
        println!(
            "strawwu: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=SKIP subsystem=non-gui)",
            req.binary_path.display(),
            req.format,
            exec.pid,
            profile.execution_backend,
            app_id,
            mode,
        );
    }

    if let Some(ref se) = exec.side_effects {
        if !se.stdout_utf8.is_empty() {
            print!("{}", se.stdout_utf8);
        }
        let _ = log::append_event(
            "pe_side_effects",
            &serde_json::json!({
                "mode": mode,
                "cpu_executed": exec.cpu_executed,
                "stdout": se.stdout_utf8,
                "host_files": se.host_files_written,
                "exit_code": se.exit_code,
                "instructions_retired": se.instructions_retired,
                "halt": exec.halt_reason,
                "apis": se.apis_invoked,
                "gui": se.gui,
            }),
        );
    }

    if let Some(path) = desktop_entry {
        let _ = log::append_event(
            "desktop_entry",
            &serde_json::json!({
                "app_id": app_id,
                "path": path,
                "from_open": from_open,
                "backend": backend_name,
            }),
        );
    }

    Ok(())
}

fn print_help() {
    println!(
        "strawwu {VERSION} — StrawWU portable Windows app launcher

USAGE:
    strawwu <COMMAND> [OPTIONS]

COMMANDS:
    open <file.exe|.msi> [--auto|--run|--install]
        Click-to-open via native strawwu-nt (execution_backend=native)
    run <binary> [--backend native|container|microvm] [--bundle a,b,c]
        Default backend=native (self-built PE / strawwu-nt)
    install <installer.exe|.msi>
        Register + run the installer through native strawwu-nt
    integrate
        Enable double-click for .exe/.msi (MIME + desktop handler)
    apps list
    devices list [--json]
    mfp smoke [--json]
    profile inspect|export <app-id>
    repair <app-id>
    status
    version
    help

CLICK TO INSTALL & LAUNCH:
    1) curl …/install.sh | bash
    2) strawwu integrate          # if needed after desktop change
    3) double-click any .exe/.msi — native strawwu-nt path
    4) relaunch from the app menu (~/.local/share/applications)

BACKEND:
    Default: native (STRAWWU_BACKEND unset or native)
    Override: STRAWWU_BACKEND=native|container|microvm

REGISTRY:
    run/install/open register apps in the local app-registry
    (override with STRAWWU_APP_REGISTRY)
"
    );
}
