use std::path::{Path, PathBuf};
use std::process;

use strawwu_launcher::cli::{
    self, AppsSubcommand, Command, EngineSubcommand, InteropSubcommand, MatrixSubcommand, OpenMode,
    SysappsSubcommand,
    PrefixSubcommand, RecipesSubcommand,
};
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
use strawnt_engine::{self, print_doctor_human, print_status_human};

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

                // NTW0+: MIME/open uses product default wine (proton-ge).
                // Legacy native only when STRAWNT_LEGACY_NATIVE=1 (via resolve_backend).
                if let Err(code) =
                    launch_pe(&path, &[], None, &[], true, install_mode)
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
                        // Run the installer through product default wine/GE path.
                        if let Err(code) =
                            launch_pe(&installer, &[], None, &[], false, true)
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
        Command::Integrate => match desktop::install_desktop_integration_full() {
            Ok(info) => {
                println!(
                    "strawnt: desktop integration installed\n  menu: {}\n  handler: {}\n  cleared_stale: {}\n  backend: wine (proton-ge; powered by Wine)\n  tip: app menu → StrawNT; double-click .exe / .msi to install & launch",
                    info.menu_entry.display(),
                    info.open_handler.display(),
                    info.cleared_stale.len()
                );
                open::notify(
                    "StrawNT",
                    "Click-to-open enabled for Windows .exe / .msi (wine / proton-ge; powered by Wine)",
                );
            }
            Err(e) => {
                eprintln!("strawnt: integrate failed: {e}");
                process::exit(1);
            }
        },
        Command::Apps(sub) => {
            let _ = require_repo_root("apps");
            match sub {
                AppsSubcommand::Status { json, home } => {
                    match strawnt_appmgr::status(home.as_deref()) {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps status failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::List { json, home } => {
                    match strawnt_appmgr::list_apps(home.as_deref()) {
                        Ok(v) => {
                            if json {
                                emit_json_or_human(true, &v);
                            } else {
                                let apps = v.get("apps").and_then(|a| a.as_array());
                                if apps.map(|a| a.is_empty()).unwrap_or(true) {
                                    println!("strawnt: no apps registered");
                                } else if let Some(apps) = apps {
                                    for app in apps {
                                        let id = app.get("id").and_then(|x| x.as_str()).unwrap_or("?");
                                        let name =
                                            app.get("name").and_then(|x| x.as_str()).unwrap_or("?");
                                        let kind =
                                            app.get("kind").and_then(|x| x.as_str()).unwrap_or("?");
                                        let state = app
                                            .get("install_state")
                                            .and_then(|x| x.as_str())
                                            .unwrap_or("?");
                                        println!("{id}\t{name}\t{kind}\t{state}");
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("strawnt apps list failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Show { id, json, home } => {
                    match strawnt_appmgr::show_app(&id, home.as_deref()) {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps show failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Install {
                    target,
                    prefix,
                    json,
                    home,
                } => {
                    let path = PathBuf::from(&target);
                    let result = if path.exists() {
                        strawnt_appmgr::install_path(&path, prefix.as_deref(), home.as_deref())
                    } else {
                        strawnt_appmgr::install_catalog(&target, prefix.as_deref(), home.as_deref())
                    };
                    match result {
                        Ok(v) => {
                            emit_json_or_human(json, &v);
                            if v.get("status").and_then(|s| s.as_str()) == Some("FAIL") {
                                process::exit(1);
                            }
                        }
                        Err(e) => {
                            eprintln!("strawnt apps install failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Uninstall { id, json, home } => {
                    match strawnt_appmgr::uninstall_app(&id, home.as_deref()) {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps uninstall failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Launch { id, json, home } => {
                    // NTW6: dedicated system apps launch via strawnt-sysapps.
                    if let Some(role) = strawnt_sysapps::DedicatedRole::from_app_id(&id) {
                        match strawnt_sysapps::launch_role(role, home.as_deref(), None) {
                            Ok(v) => {
                                emit_json_or_human(json, &v);
                                if v.get("status").and_then(|s| s.as_str()) == Some("FAIL") {
                                    process::exit(1);
                                }
                            }
                            Err(e) => {
                                eprintln!("strawnt apps launch (sysapp) failed: {e}");
                                process::exit(1);
                            }
                        }
                    } else {
                        match strawnt_appmgr::launch_app(&id, home.as_deref()) {
                            Ok(v) => {
                                emit_json_or_human(json, &v);
                                if v.get("status").and_then(|s| s.as_str()) == Some("FAIL") {
                                    process::exit(1);
                                }
                            }
                            Err(e) => {
                                eprintln!("strawnt apps launch failed: {e}");
                                process::exit(1);
                            }
                        }
                    }
                }
                AppsSubcommand::Prefix {
                    id,
                    set_to,
                    json,
                    home,
                } => match strawnt_appmgr::app_prefix(&id, set_to.as_deref(), home.as_deref()) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt apps prefix failed: {e}");
                        process::exit(1);
                    }
                },
                AppsSubcommand::Recipes {
                    id,
                    apply,
                    json,
                    home,
                } => match strawnt_appmgr::app_recipes(&id, apply.as_deref(), home.as_deref()) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt apps recipes failed: {e}");
                        process::exit(1);
                    }
                },
                AppsSubcommand::Channel {
                    set_to,
                    json,
                    home,
                } => {
                    let result = if let Some(ch) = set_to {
                        strawnt_appmgr::set_channel(&ch, home.as_deref())
                    } else {
                        strawnt_appmgr::get_channel(home.as_deref())
                    };
                    match result {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps channel failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Permissions {
                    id,
                    grant,
                    revoke,
                    json,
                    home,
                } => {
                    let result = if let (Some(app_id), Some(cap)) = (id.as_ref(), grant.as_ref()) {
                        strawnt_appmgr::grant_permission(app_id, cap, home.as_deref())
                    } else if let (Some(app_id), Some(cap)) = (id.as_ref(), revoke.as_ref()) {
                        strawnt_appmgr::revoke_permission(app_id, cap, home.as_deref())
                    } else {
                        strawnt_appmgr::list_permissions(id.as_deref(), home.as_deref())
                    };
                    match result {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps permissions failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Compat { id, json, home } => {
                    match strawnt_appmgr::app_compat(&id, home.as_deref()) {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps compat failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Catalog { json } => match strawnt_appmgr::list_catalog() {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt apps catalog failed: {e}");
                        process::exit(1);
                    }
                },
                AppsSubcommand::Sysapps { json, home } => {
                    match strawnt_appmgr::list_sysapps(home.as_deref()) {
                        Ok(v) => emit_json_or_human(json, &v),
                        Err(e) => {
                            eprintln!("strawnt apps sysapps failed: {e}");
                            process::exit(1);
                        }
                    }
                }
                AppsSubcommand::Smoke { json, home } => {
                    match strawnt_appmgr::run_appmgr_smoke(home.as_deref()) {
                        Ok(v) => {
                            emit_json_or_human(json, &v);
                            if v.get("status").and_then(|s| s.as_str()) != Some("PASS") {
                                process::exit(1);
                            }
                        }
                        Err(e) => {
                            eprintln!("strawnt apps smoke failed: {e}");
                            process::exit(1);
                        }
                    }
                }
            }
        }
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
                if legacy_native_enabled() {
                    println!("strawnt: execution_backend=native (legacy unsupported)");
                    println!("strawnt: default backend=native (STRAWNT_LEGACY_NATIVE=1)");
                } else {
                    println!("strawnt: execution_backend=wine (proton-ge)");
                    println!("strawnt: default backend=wine");
                    println!("strawnt: powered by Wine");
                }
            }
            Err(e) => {
                eprintln!("strawnt: status failed: {e}");
                process::exit(1);
            }
        },
        Command::Engine(EngineSubcommand::Status { json }) => {
            let root = match strawnt_engine::find_repo_root() {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("strawnt engine: {e}");
                    process::exit(1);
                }
            };
            match strawnt_engine::engine_status(&root) {
                Ok(s) => {
                    if json {
                        println!("{}", serde_json::to_string_pretty(&s).unwrap_or_default());
                    } else {
                        print_status_human(&s);
                    }
                    if s.status == "FAIL" {
                        process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("strawnt engine status failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Engine(EngineSubcommand::Hello { json }) => {
            let root = match strawnt_engine::find_repo_root() {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("strawnt engine: {e}");
                    process::exit(1);
                }
            };
            let prefix = std::env::temp_dir().join(format!(
                "strawnt-engine-hello-{}",
                std::process::id()
            ));
            match strawnt_engine::run_hello_cmd(&root, &prefix) {
                Ok(r) => {
                    if json {
                        println!("{}", serde_json::to_string_pretty(&r).unwrap_or_default());
                    } else {
                        println!(
                            "strawnt engine hello: status={} backend={} pin={} exit={}",
                            r.status, r.backend, r.pin, r.exit_code
                        );
                        if !r.stdout.trim().is_empty() {
                            print!("{}", r.stdout);
                            if !r.stdout.ends_with('\n') {
                                println!();
                            }
                        }
                    }
                    let _ = std::fs::remove_dir_all(&prefix);
                    if r.status != "PASS" {
                        process::exit(1);
                    }
                }
                Err(e) => {
                    let _ = std::fs::remove_dir_all(&prefix);
                    eprintln!("strawnt engine hello failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Doctor { json } => {
            let root = match strawnt_engine::find_repo_root() {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("strawnt doctor: {e}");
                    process::exit(1);
                }
            };
            match strawnt_engine::doctor(&root) {
                Ok(d) => {
                    if json {
                        println!("{}", serde_json::to_string_pretty(&d).unwrap_or_default());
                    } else {
                        print_doctor_human(&d);
                    }
                    if d.status == "FAIL" || !d.wine.found {
                        process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("strawnt doctor failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Prefix(sub) => match sub {
            PrefixSubcommand::Create {
                name,
                arch,
                force,
                json,
                home,
            } => {
                let root = require_repo_root("prefix");
                match strawnt_engine::prefix::create_prefix(
                    &root,
                    &name,
                    &arch,
                    force,
                    home.as_deref(),
                ) {
                    Ok(v) => {
                        emit_json_or_human(json, &v);
                        if v.get("status").and_then(|s| s.as_str()) == Some("FAIL") {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt prefix create failed: {e}");
                        process::exit(1);
                    }
                }
            }
            PrefixSubcommand::List { json, home } => {
                match strawnt_engine::prefix::list_prefixes(home.as_deref()) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt prefix list failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Recipes(sub) => match sub {
            RecipesSubcommand::List { json } => {
                let v = strawnt_engine::recipes::list_recipes();
                emit_json_or_human(json, &v);
            }
            RecipesSubcommand::Plan { id, json } => {
                match strawnt_engine::recipes::plan_recipe(&id) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt recipes plan failed: {e}");
                        process::exit(1);
                    }
                }
            }
            RecipesSubcommand::Apply {
                id,
                prefix,
                json,
                home,
            } => {
                let root = require_repo_root("recipes");
                match strawnt_engine::recipes::apply_recipe(
                    &root,
                    &id,
                    &prefix,
                    home.as_deref(),
                ) {
                    Ok(v) => {
                        emit_json_or_human(json, &v);
                        let st = v.get("status").and_then(|s| s.as_str()).unwrap_or("FAIL");
                        if st == "FAIL" {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt recipes apply failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Matrix(sub) => match sub {
            MatrixSubcommand::List { json, home } => {
                match strawnt_engine::matrix::list_matrix(home.as_deref()) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt matrix list failed: {e}");
                        process::exit(1);
                    }
                }
            }
            MatrixSubcommand::Get {
                app_key,
                json,
                home,
            } => match strawnt_engine::matrix::get_entry(&app_key, home.as_deref()) {
                Ok(v) => emit_json_or_human(json, &v),
                Err(e) => {
                    eprintln!("strawnt matrix get failed: {e}");
                    process::exit(1);
                }
            },
            MatrixSubcommand::Set {
                name,
                status,
                notes,
                prefix,
                json,
                home,
            } => match strawnt_engine::matrix::set_entry(
                &name,
                &status,
                &notes,
                prefix.as_deref(),
                None,
                None,
                home.as_deref(),
            ) {
                Ok(v) => emit_json_or_human(json, &v),
                Err(e) => {
                    eprintln!("strawnt matrix set failed: {e}");
                    process::exit(1);
                }
            },
            MatrixSubcommand::Seed { json, home } => {
                let root = require_repo_root("matrix");
                let pin = match strawnt_engine::load_pin(&root) {
                    Ok(p) => p.tag,
                    Err(e) => {
                        eprintln!("strawnt matrix seed: {e}");
                        process::exit(1);
                    }
                };
                match strawnt_engine::matrix::seed_golden(home.as_deref(), &pin) {
                    Ok(v) => {
                        emit_json_or_human(json, &v);
                        if v.get("status").and_then(|s| s.as_str()) != Some("PASS") {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt matrix seed failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Bench {
            profile,
            json,
            home,
        } => {
            let root = require_repo_root("bench");
            let profile = match strawnt_engine::optimize::OptProfile::parse(&profile) {
                Ok(p) => p,
                Err(e) => {
                    eprintln!("strawnt bench: {e}");
                    process::exit(1);
                }
            };
            match strawnt_engine::optimize::run_bench(&root, home.as_deref(), profile) {
                Ok(v) => {
                    emit_json_or_human(json, &v);
                    let st = v.get("status").and_then(|s| s.as_str()).unwrap_or("FAIL");
                    if st == "FAIL" {
                        process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("strawnt bench failed: {e}");
                    process::exit(1);
                }
            }
        }
        Command::Interop(sub) => match sub {
            InteropSubcommand::Status { json } => {
                let root = require_repo_root("interop");
                let spec = root.join("docs/specs/interop-win32-ipc.md");
                let fixtures_ok = match strawnt_interop::smoke::ensure_fixtures(&root) {
                    Ok((ac, game)) => ac.is_file() && game.is_file(),
                    Err(_) => false,
                };
                let pin = strawnt_engine::load_pin(&root).ok();
                let v = serde_json::json!({
                    "command": "interop status",
                    "product": "StrawNT",
                    "stage": "ntw4-win32-ipc",
                    "execution_backend": "wine",
                    "backend": "wine",
                    "engine": "proton-ge",
                    "pin": pin.as_ref().map(|p| p.tag.clone()),
                    "powered_by_wine": true,
                    "spec_present": spec.is_file(),
                    "fixtures_built": fixtures_ok,
                    "default_broker_port": strawnt_interop::broker::DEFAULT_PORT,
                    "claims": {
                        "ranked_pass_claimed": false,
                        "full_windows_claimed": false
                    },
                    "status": if spec.is_file() { "PASS" } else { "FAIL" },
                    "notes": [
                        "same_prefix=named pipes; cross_prefix=host broker + capability grant",
                        "powered by Wine — not a ranked anti-cheat claim"
                    ]
                });
                emit_json_or_human(json, &v);
                if v.get("status").and_then(|s| s.as_str()) != Some("PASS") {
                    process::exit(1);
                }
            }
            InteropSubcommand::Smoke { json, home } => {
                let _root = require_repo_root("interop");
                match strawnt_interop::run_interop_smoke(home.as_deref()) {
                    Ok(mut v) => {
                        if let Ok(ver) = std::fs::read_to_string(
                            strawnt_engine::find_repo_root()
                                .map(|r| r.join("VERSION"))
                                .unwrap_or_default(),
                        ) {
                            v.as_object_mut().map(|o| {
                                o.insert(
                                    "version".into(),
                                    serde_json::Value::String(ver.trim().to_string()),
                                )
                            });
                        }
                        if let Ok(head) = std::process::Command::new("git")
                            .args(["rev-parse", "HEAD"])
                            .output()
                        {
                            if head.status.success() {
                                let h = String::from_utf8_lossy(&head.stdout).trim().to_string();
                                v.as_object_mut().map(|o| {
                                    o.insert("git_head".into(), serde_json::Value::String(h))
                                });
                            }
                        }
                        let ts = chrono_like_utc();
                        v.as_object_mut().map(|o| {
                            o.insert("generated_at".into(), serde_json::Value::String(ts))
                        });
                        emit_json_or_human(json, &v);
                        let st = v.get("status").and_then(|s| s.as_str()).unwrap_or("FAIL");
                        if st != "PASS" {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt interop smoke failed: {e}");
                        process::exit(1);
                    }
                }
            }
            InteropSubcommand::Grant {
                token,
                channel,
                prefixes,
                json,
            } => {
                let grant = strawnt_interop::Grant {
                    token,
                    channel,
                    prefixes,
                };
                let v = serde_json::json!({
                    "command": "interop grant",
                    "status": "PASS",
                    "grant": grant,
                    "notes": [
                        "Ephemeral grant record for App Manager / interopd control plane",
                        "Live cross-prefix AUTH still requires broker-loaded grant",
                        "ranked_pass_claimed=false"
                    ],
                    "claims": { "ranked_pass_claimed": false }
                });
                emit_json_or_human(json, &v);
            }
        },
        Command::Sysapps(sub) => match sub {
            SysappsSubcommand::List { json, home } => {
                match strawnt_sysapps::list_apps(home.as_deref()) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt sysapps list failed: {e}");
                        process::exit(1);
                    }
                }
            }
            SysappsSubcommand::Launch {
                role,
                arg,
                json,
                home,
            } => {
                let role = match role.parse::<strawnt_sysapps::DedicatedRole>() {
                    Ok(r) => r,
                    Err(e) => {
                        eprintln!("strawnt sysapps launch: {e}");
                        process::exit(1);
                    }
                };
                match strawnt_sysapps::launch_role(role, home.as_deref(), arg.as_deref()) {
                    Ok(v) => {
                        emit_json_or_human(json, &v);
                        if v.get("status").and_then(|s| s.as_str()) == Some("FAIL") {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt sysapps launch failed: {e}");
                        process::exit(1);
                    }
                }
            }
            SysappsSubcommand::Manifest { role, json } => {
                let role = match role.parse::<strawnt_sysapps::DedicatedRole>() {
                    Ok(r) => r,
                    Err(e) => {
                        eprintln!("strawnt sysapps manifest: {e}");
                        process::exit(1);
                    }
                };
                match strawnt_sysapps::load_manifest(role) {
                    Ok(v) => emit_json_or_human(json, &v),
                    Err(e) => {
                        eprintln!("strawnt sysapps manifest failed: {e}");
                        process::exit(1);
                    }
                }
            }
            SysappsSubcommand::Smoke { json, home } => {
                match strawnt_sysapps::run_sysapps_smoke(home.as_deref()) {
                    Ok(v) => {
                        emit_json_or_human(json, &v);
                        if v.get("status").and_then(|s| s.as_str()) != Some("PASS") {
                            process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("strawnt sysapps smoke failed: {e}");
                        process::exit(1);
                    }
                }
            }
        },
        Command::Config(_) => {
            println!("strawnt: config (stub)");
        }
    }
}

fn require_repo_root(ctx: &str) -> PathBuf {
    match strawnt_engine::find_repo_root() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("strawnt {ctx}: {e}");
            process::exit(1);
        }
    }
}

fn emit_json_or_human(json: bool, v: &serde_json::Value) {
    if json {
        println!("{}", serde_json::to_string_pretty(v).unwrap_or_default());
    } else {
        println!("{}", serde_json::to_string_pretty(v).unwrap_or_default());
    }
}

fn chrono_like_utc() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Prefer `date -u` when available for RFC3339-ish stamp.
    if let Ok(out) = process::Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output()
    {
        if out.status.success() {
            return String::from_utf8_lossy(&out.stdout).trim().to_string();
        }
    }
    format!("{secs}")
}

/// NTW0+: product default is **wine** (Proton-GE). Legacy native via STRAWNT_LEGACY_NATIVE=1.
fn legacy_native_enabled() -> bool {
    matches!(
        std::env::var("STRAWNT_LEGACY_NATIVE").ok().as_deref(),
        Some("1") | Some("true") | Some("TRUE") | Some("yes")
    )
}

/// Resolve execution backend. Default is **wine** (proton-ge); legacy native is opt-in only.
fn resolve_backend(requested: Option<&str>) -> String {
    match requested {
        Some(b) if !b.is_empty() => b.to_string(),
        _ if legacy_native_enabled() => "native".into(),
        _ => std::env::var("STRAWNT_BACKEND")
            .or_else(|_| std::env::var("STRAWWU_BACKEND"))
            .unwrap_or_else(|_| "wine".into()),
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

    // Always persist exec summary when side-effect dir is set (nt3 / pe6 evidence).
    // Write even when guest side_effects are absent so load/mode failures remain observable.
    if let Some(dir) = std::env::var_os("STRAWNT_PE_SIDE_EFFECT_DIR")
        .or_else(|| std::env::var_os("STRAWWU_PE_SIDE_EFFECT_DIR"))
    {
        let se = exec.side_effects.as_ref();
        let summary = serde_json::json!({
            "mode": exec.mode,
            "cpu_executed": exec.cpu_executed,
            "stdout": se.map(|s| s.stdout_utf8.clone()).unwrap_or_default(),
            "host_files": se.map(|s| s.host_files_written.clone()).unwrap_or_default(),
            "exit_code": se.and_then(|s| s.exit_code),
            "instructions_retired": se.map(|s| s.instructions_retired).unwrap_or(0),
            "halt": exec.halt_reason,
            "apis": se.map(|s| s.apis_invoked.clone()).unwrap_or_default(),
            "gui": se.and_then(|s| s.gui.clone()),
            "load": exec.load_result.as_ref().map(|l| serde_json::json!({
                "mapped_base": l.mapped_base,
                "entry_point_va": l.entry_point_va,
                "total_imports": l.total_imports,
                "resolved_imports": l.resolved_imports,
                "unresolved_imports": l.unresolved_imports,
            })),
            "error": exec.error,
            "backend": backend_name,
            "app_id": app_id,
            "binary": req.binary_path.display().to_string(),
        });
        let path = std::path::PathBuf::from(dir).join("pe-exec-summary.json");
        let _ = std::fs::write(
            &path,
            serde_json::to_string_pretty(&summary).unwrap_or_default(),
        );
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
        "strawnt {VERSION} — StrawNT Wine/Proton-GE runtime (powered by Wine)

USAGE:
    strawnt <COMMAND> [OPTIONS]

COMMANDS:
    open <file.exe|.msi> [--auto|--run|--install]
        Click-to-open via Wine/Proton-GE (execution_backend=wine; powered by Wine)
    run <binary> [--backend wine|native|container|microvm] [--bundle a,b,c]
        Default backend=wine (proton-ge); legacy native via STRAWNT_LEGACY_NATIVE=1
    install <installer.exe|.msi>
        Install via wine/GE path → app-registry + shortcut; else pending + run
    integrate
        Enable double-click for .exe/.msi (MIME + desktop handler)
    apps status|list|show|install|uninstall|launch|prefix|recipes|channel|permissions|compat|catalog|sysapps|smoke [--json] [--home DIR]
        NTW5 system App Manager (install/list/launch/prefix/deps/channel/perms/catalog)
    sysapps list|launch|manifest|smoke [--json] [--home DIR]
        NTW6 dedicated system apps (settings/run/installer/library/compat/taskmgr/files)
    devices list [--json]
    mfp smoke [--json]
    profile inspect|export <app-id>
    repair <app-id>
    status
    engine status [--json]
        Vendored Proton-GE pin + wine path (NTW1)
    engine hello [--json]
        Smoke cmd.exe echo via vendored Proton-GE wine
    doctor [--json]
        Engine health: pin, wine binary, powered by Wine
    prefix create <name> [--arch win64] [--force] [--home DIR] [--json]
        Create Wine prefix under ~/.local/share/strawnt/prefixes (NTW2)
    prefix list [--home DIR] [--json]
    recipes list|plan <id>|apply <id> --prefix <name> [--home DIR] [--json]
        Recipes: vcrun, corefonts, dxvk, fontsmooth, crypt32-signature (NTW2)
    matrix list|get <key>|set <name> <status>|seed [--home DIR] [--json]
        Honest PASS/PARTIAL/FAIL/UNKNOWN matrix; seed line.exe+steam.exe (NTW2)
    bench [--profile baseline|optimized] [--home DIR] [--json]
        NTW3 measurable Wine/GE bench (cold start / RSS / prefix create)
    interop status|smoke|grant [--home DIR] [--json]
        NTW4 Win32 IPC: same_prefix pipes + cross_prefix host broker
        (not a ranked / vendor anti-cheat PASS)
    version
    help

CLICK TO INSTALL & LAUNCH:
    1) curl …/install.sh | bash
    2) strawnt integrate          # if needed after desktop change
    3) double-click any .exe/.msi — wine/proton-ge path
    4) relaunch from the app menu (~/.local/share/applications)

BACKEND:
    Default: wine (STRAWNT_BACKEND unset; engine=proton-ge; powered by Wine)
    Override: STRAWNT_BACKEND=wine|native|container|microvm
    Legacy: STRAWNT_LEGACY_NATIVE=1 (unsupported research path)
    Prefix create: template clone by default (STRAWNT_PREFIX_MODE=wineboot to force)

REGISTRY:
    run/install/open register apps in the local app-registry
    (override with STRAWNT_APP_REGISTRY; STRAWWU_* accepted as compat)
"
    );
}
