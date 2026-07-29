use std::path::{Path, PathBuf};
use std::process;

use strawwu_launcher::cli::{self, Command, OpenMode};
use strawwu_launcher::desktop;
use strawwu_launcher::detect::{detect_from_path, BinaryFormat};
use strawwu_launcher::install_native;
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
// filter) when a downstream reader closes the pipe early — e.g. `strawnt ... |
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
            eprintln!("strawnt: {e}");
            process::exit(1);
        }
    };

    match cmd {
        Command::Version => {
            println!("strawnt {VERSION}");
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

            if install_mode && install_native::installer_has_native_package(&path) {
                match install_native::native_install(&path) {
                    Ok(report) => {
                        println!(
                            "strawnt: open/install native unpack app_id={} type={} install_path={} main={} desktop={} backend=native mode=real files={}",
                            report.app_id,
                            report.installer_type,
                            report.install_path,
                            report.main_exe,
                            report.desktop_entry.as_deref().unwrap_or("-"),
                            report.files.len()
                        );
                        let _ = log::append_event("native_install", &report);
                        let main = PathBuf::from(&report.main_exe);
                        open::notify(
                            "StrawNT",
                            &format!("Installing & launching {}", report.app_name),
                        );
                        if let Err(code) = launch_pe_with_registry(
                            &main,
                            &[],
                            Some("native"),
                            &[],
                            true,
                            false,
                            Some(&report.app_id),
                        ) {
                            open::notify("StrawNT", &format!("Failed to open {}", report.app_name));
                            process::exit(code);
                        }
                        open::notify(
                            "StrawNT",
                            &format!("{} ready — also available from the app menu", report.app_name),
                        );
                    }
                    Err(e) => {
                        eprintln!("strawnt: native install failed: {e}");
                        process::exit(1);
                    }
                }
            } else {
                if install_mode {
                    match registry::register_install(&path) {
                        Ok(app_id) => {
                            println!(
                                "strawnt: open/install registered pending app_id={app_id} ({})",
                                path.display()
                            );
                        }
                        Err(e) => {
                            eprintln!("strawnt: open install register failed: {e}");
                            process::exit(1);
                        }
                    }
                }

                let name = derive_app_name(&path);
                open::notify(
                    "StrawNT",
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

                // Double-click / MIME open always pins native (no Wine env override).
                if let Err(code) =
                    launch_pe(&path, &[], Some("native"), &[], true, install_mode)
                {
                    open::notify("StrawNT", &format!("Failed to open {name}"));
                    process::exit(code);
                }
                open::notify(
                    "StrawNT",
                    &format!("{name} ready — also available from the app menu"),
                );
            }
        }
        Command::Install { installer } => {
            if install_native::installer_has_native_package(&installer) {
                match install_native::native_install(&installer) {
                    Ok(report) => {
                        println!(
                            "strawnt: install {} (native unpack app_id={}; type={}; install_path={}; desktop={}; backend=native; mode=real)",
                            installer.display(),
                            report.app_id,
                            report.installer_type,
                            report.install_path,
                            report.desktop_entry.as_deref().unwrap_or("-"),
                        );
                        let _ = log::append_event("native_install", &report);
                        // Launch the unpacked main.exe through the same native path
                        // without clobbering the installer registry entry / shortcut.
                        let main = PathBuf::from(&report.main_exe);
                        if let Err(code) = launch_pe_with_registry(
                            &main,
                            &[],
                            Some("native"),
                            &[],
                            false,
                            false,
                            Some(&report.app_id),
                        ) {
                            open::notify(
                                "StrawNT",
                                &format!("Installed main launch failed: {}", report.app_name),
                            );
                            process::exit(code);
                        }
                        open::notify(
                            "StrawNT",
                            &format!(
                                "{} installed — use the app menu or strawnt open to launch",
                                report.app_name
                            ),
                        );
                    }
                    Err(e) => {
                        eprintln!("strawnt: native install failed: {e}");
                        process::exit(1);
                    }
                }
            } else {
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
                                    "strawnt: install {} (registered pending app_id={app_id}; desktop={})",
                                    installer.display(),
                                    path.display()
                                );
                            }
                            Err(e) => {
                                println!(
                                    "strawnt: install {} (registered pending app_id={app_id}; desktop skipped: {e})",
                                    installer.display()
                                );
                            }
                        }
                        // Run the installer through the native strawnt-native path.
                        if let Err(code) =
                            launch_pe(&installer, &[], Some("native"), &[], false, true)
                        {
                            open::notify("StrawNT", &format!("Install failed: {app_name}"));
                            process::exit(code);
                        }
                        open::notify(
                            "StrawNT",
                            &format!("{app_name} installed — use the app menu or strawnt open to launch"),
                        );
                    }
                    Err(e) => {
                        eprintln!("strawnt: registry register failed: {e}");
                        process::exit(1);
                    }
                }
            }
        }
        Command::Integrate => match desktop::install_desktop_integration() {
            Ok(path) => {
                println!(
                    "strawnt: desktop integration installed\n  handler: {}\n  backend: native (strawnt-native)\n  tip: double-click .exe / .msi to install & launch",
                    path.display()
                );
                open::notify(
                    "StrawNT",
                    "Click-to-open enabled for Windows .exe / .msi (native)",
                );
            }
            Err(e) => {
                eprintln!("strawnt: integrate failed: {e}");
                process::exit(1);
            }
        },
        Command::Apps(sub) => match sub {
            cli::AppsSubcommand::List => match registry::list_registered_apps() {
                Ok(apps) if apps.is_empty() => {
                    println!("strawnt: no apps registered");
                }
                Ok(apps) => {
                    for (id, name, kind) in apps {
                        println!("{id}\t{name}\t{kind}");
                    }
                }
                Err(e) => {
                    eprintln!("strawnt: registry list failed: {e}");
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
                        eprintln!("strawnt: devices list failed: {e}");
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
                        eprintln!("strawnt: mfp smoke failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Profile(_) => {
            println!("strawnt: profile (stub)");
        }
        Command::Repair { app_id } => {
            println!("strawnt: repair {app_id} (stub)");
        }
        Command::Status => match registry::list_registered_apps() {
            Ok(apps) => {
                let sessions = RuntimeOrchestrator::new().session_count();
                println!(
                    "strawnt: status — runtime idle, {} session(s), {} app(s) registered",
                    sessions,
                    apps.len()
                );
                println!("strawnt: execution_backend=native (strawnt-native)");
                println!("strawnt: default backend=native");
            }
            Err(e) => {
                eprintln!("strawnt: status failed: {e}");
                process::exit(1);
            }
        },
        Command::Config(_) => {
            println!("strawnt: config (stub)");
        }
    }
}

/// Resolve execution backend. Default is **native** (self-built strawnt-native).
fn resolve_backend(requested: Option<&str>) -> String {
    match requested {
        Some(b) if !b.is_empty() => b.to_string(),
        _ => std::env::var("STRAWNT_BACKEND")
            .or_else(|_| std::env::var("STRAWWU_BACKEND"))
            .unwrap_or_else(|_| "native".into()),
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
    launch_pe_with_registry(binary, app_args, backend, bundle, from_open, true, None)
}

/// Like [`launch_pe`], but can skip registry/desktop mutation and force an app_id.
fn launch_pe_with_registry(
    binary: &Path,
    app_args: &[String],
    backend: Option<&str>,
    bundle: &[PathBuf],
    from_open: bool,
    update_registry: bool,
    forced_app_id: Option<&str>,
) -> Result<(), i32> {
    let format = detect_from_path(binary).unwrap_or(BinaryFormat::Unknown);
    let backend_name = resolve_backend(backend);
    let mut req = LaunchRequest::new(binary.to_path_buf(), format).with_args(app_args.to_vec());
    req = req.with_backend(&backend_name);
    if !bundle.is_empty() {
        req = req.with_bundle(bundle.to_vec());
    }

    if let Err(e) = req.validate() {
        eprintln!("strawnt: launch validation failed: {e}");
        return Err(1);
    }

    let app_name = derive_app_name(binary);
    let app_id_default = registry::derive_app_id(binary);
    let app_id_str = forced_app_id.unwrap_or(app_id_default.as_str());

    let (desktop_entry, app_id) = if update_registry {
        let desktop_path =
            desktop::write_launcher_desktop(app_id_str, binary, Some(&app_name));

        let desktop_entry = match desktop_path {
            Ok(path) => {
                if from_open {
                    println!("strawnt: desktop launcher → {}", path.display());
                }
                Some(path.to_string_lossy().into_owned())
            }
            Err(e) => {
                eprintln!("strawnt: desktop entry skipped: {e}");
                None
            }
        };

        let app_id = match registry::register_launch(
            binary,
            format,
            Some(backend_name.as_str()),
            desktop_entry.clone(),
        ) {
            Ok(id) => {
                if forced_app_id.is_some() && id != app_id_str {
                    // register_launch derives id from stem; keep caller's id in messages.
                    app_id_str.to_string()
                } else {
                    id
                }
            }
            Err(e) => {
                eprintln!("strawnt: registry register failed: {e}");
                return Err(1);
            }
        };
        (desktop_entry, app_id)
    } else {
        (None, app_id_str.to_string())
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
            eprintln!("strawnt: PE load failed: {e}");
            return Err(1);
        }
    };

    let mut orch = RuntimeOrchestrator::new();
    let mut profile = AppProfile::default_win32(app_id);
    profile.execution_backend = backend_name.to_string();

    let side_dir = std::env::var_os("STRAWNT_PE_SIDE_EFFECT_DIR").or_else(|| std::env::var_os("STRAWWU_PE_SIDE_EFFECT_DIR")).map(std::path::PathBuf::from);
    let exec = strawwu_runtime::execute_pe_with_side_effect_dir(
        &mut orch,
        &profile,
        &pe_data,
        side_dir,
    );
    if exec.state != ExecState::Running {
        eprintln!(
            "strawnt: launch failed: {}",
            exec.error.unwrap_or_else(|| "unknown error".into())
        );
        return Err(1);
    }

    // Always persist exec summary when side-effect dir is set (pe6 golden evidence).
    if let Some(ref se) = exec.side_effects {
        if let Some(dir) = std::env::var_os("STRAWNT_PE_SIDE_EFFECT_DIR").or_else(|| std::env::var_os("STRAWWU_PE_SIDE_EFFECT_DIR")) {
            let summary = serde_json::json!({
                "mode": exec.mode,
                "cpu_executed": exec.cpu_executed,
                "stdout": se.stdout_utf8,
                "host_files": se.host_files_written,
                "exit_code": se.exit_code,
                "instructions_retired": se.instructions_retired,
                "halt": exec.halt_reason,
                "apis": se.apis_invoked,
                "gui": se.gui,
                "load": exec.load_result.as_ref().map(|l| serde_json::json!({
                    "mapped_base": l.mapped_base,
                    "entry_point_va": l.entry_point_va,
                    "total_imports": l.total_imports,
                    "resolved_imports": l.resolved_imports,
                    "unresolved_imports": l.unresolved_imports,
                })),
                "backend": "native",
                "app_id": app_id,
                "binary": req.binary_path.display().to_string(),
            });
            let path = std::path::PathBuf::from(dir).join("pe-exec-summary.json");
            let _ = std::fs::write(
                &path,
                serde_json::to_string_pretty(&summary).unwrap_or_default(),
            );
        }
    }

    let mode = exec.mode.as_str();
    if mode == "simulated" && std::env::var_os("STRAWNT_REQUIRE_REAL_EXEC").or_else(|| std::env::var_os("STRAWWU_REQUIRE_REAL_EXEC")).is_some() {
        eprintln!("strawnt: real CPU execution required but mode=simulated");
        return Err(1);
    }

    let gui = match maybe_run_gui_smoke(&pe_data, app_id, app_name) {
        Ok(result) => result,
        Err(e) => {
            eprintln!("strawnt: gui-smoke failed: {e}");
            return Err(1);
        }
    };

    let cpu_gui = exec.side_effects.as_ref().and_then(|se| se.gui.as_ref());
    if let Some(g) = cpu_gui {
        let _ = log::append_event("gui_cpu", g);
        println!(
            "strawnt: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=PASS hwnd={} compositor={} visible={} closed={} frames={} cpu-user32=1)",
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
            "strawnt: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=PASS hwnd={} compositor={} visible={})",
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
            "strawnt: launched {} (format={}, pid={}, backend={}, app_id={}, mode={}, gui-smoke=SKIP subsystem=non-gui)",
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
        "strawnt {VERSION} — StrawNT native PE / NT ABI runtime

USAGE:
    strawnt <COMMAND> [OPTIONS]

COMMANDS:
    open <file.exe|.msi> [--auto|--run|--install]
        Click-to-open via native strawnt-native (execution_backend=native)
    run <binary> [--backend native|container|microvm] [--bundle a,b,c]
        Default backend=native (self-built PE / strawnt-native)
    install <installer.exe|.msi>
        Native unpack (SWUP/SWUM) → app-registry + shortcut; else pending + run
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
    2) strawnt integrate          # if needed after desktop change
    3) double-click any .exe/.msi — native strawnt-native path
    4) relaunch from the app menu (~/.local/share/applications)

BACKEND:
    Default: native (STRAWNT_BACKEND / STRAWWU_BACKEND unset or native)
    Override: STRAWNT_BACKEND=native|container|microvm

REGISTRY:
    run/install/open register apps in the local app-registry
    (override with STRAWNT_APP_REGISTRY; STRAWWU_* accepted as compat)
"
    );
}
