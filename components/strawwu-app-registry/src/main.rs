use std::path::PathBuf;
use std::process;

use strawwu_app_registry::cli::{self, Command};
use strawwu_app_registry::{
    default_registry_path, load_registry_file, RegistryError, RegistryStore, ScanOptions,
};

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = match cli::parse_args(&args) {
        Ok(cmd) => cmd,
        Err(e) => {
            eprintln!("strawwu-app-registry: {e}");
            process::exit(1);
        }
    };

    if let Err(code) = run(cmd) {
        process::exit(code);
    }
}

fn run(cmd: Command) -> Result<(), i32> {
    match cmd {
        Command::Version => {
            println!("strawwu-app-registry {VERSION}");
            Ok(())
        }
        Command::Help => {
            print_help();
            Ok(())
        }
        Command::List { json } => cmd_list(json),
        Command::Show { id, json } => cmd_show(&id, json),
        Command::Register {
            id,
            name,
            kind,
            source,
            install_path,
            desktop_entry,
            protected,
            backend,
        } => cmd_register(
            id,
            name,
            kind,
            source,
            install_path,
            desktop_entry,
            protected,
            backend,
        ),
        Command::Remove { id, dry_run, json } => cmd_remove(&id, dry_run, json),
        Command::RemoveByDesktop {
            desktop,
            dry_run,
            json,
        } => cmd_remove_by_desktop(&desktop, dry_run, json),
        Command::Validate { path } => cmd_validate(path),
        Command::Scan {
            linux,
            flatpak,
            dry_run,
            json,
            ..
        } => cmd_scan(linux, flatpak, dry_run, json),
    }
}

fn cmd_list(json: bool) -> Result<(), i32> {
    let store = open_store()?;
    let apps = store.list_active();
    if json {
        println!("{}", serde_json::to_string_pretty(&apps).unwrap());
    } else if apps.is_empty() {
        println!("strawwu-app-registry: no apps registered");
    } else {
        for app in apps {
            let protected = if app.protected { " protected" } else { "" };
            println!(
                "{}  {}  ({:?}, {:?}){}",
                app.id, app.name, app.kind, app.install_state, protected
            );
        }
    }
    Ok(())
}

fn cmd_show(id: &str, json: bool) -> Result<(), i32> {
    let store = open_store()?;
    match store.get(id) {
        Some(app) => {
            if json {
                println!("{}", serde_json::to_string_pretty(app).unwrap());
            } else {
                println!("id: {}", app.id);
                println!("name: {}", app.name);
                println!("kind: {:?}", app.kind);
                println!("source: {:?}", app.source);
                println!("state: {:?}", app.install_state);
                println!("protected: {}", app.protected);
                if let Some(ref path) = app.install_path {
                    println!("install_path: {path}");
                }
            }
            Ok(())
        }
        None => {
            eprintln!("strawwu-app-registry: app not found: {id}");
            Err(1)
        }
    }
}

fn cmd_register(
    id: String,
    name: String,
    kind: strawwu_app_registry::AppKind,
    source: strawwu_app_registry::AppSource,
    install_path: Option<String>,
    desktop_entry: Option<String>,
    protected: bool,
    backend: Option<strawwu_app_registry::ExecutionBackend>,
) -> Result<(), i32> {
    let mut store = open_store()?;
    match store.register_new(
        &id, &name, kind, source, install_path, desktop_entry, protected, backend,
    ) {
        Ok(app) => {
            println!(
                "strawwu-app-registry: registered {} ({})",
                app.id, app.name
            );
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: register failed: {e}");
            Err(exit_code(&e))
        }
    }
}

fn cmd_remove(id: &str, dry_run: bool, json: bool) -> Result<(), i32> {
    let mut store = open_store()?;
    match store.remove(id, dry_run) {
        Ok(preview) => {
            if json {
                println!("{}", serde_json::to_string_pretty(&preview).unwrap());
            } else if dry_run {
                println!("strawwu-app-registry: dry-run remove {id} ({})", preview.name);
            } else {
                println!("strawwu-app-registry: removed {id} ({})", preview.name);
            }
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: remove failed: {e}");
            Err(exit_code(&e))
        }
    }
}

fn cmd_remove_by_desktop(desktop: &str, dry_run: bool, json: bool) -> Result<(), i32> {
    let mut store = open_store()?;
    match store.remove_by_desktop(desktop, dry_run) {
        Ok(preview) => {
            if json {
                println!("{}", serde_json::to_string_pretty(&preview).unwrap());
            } else if dry_run {
                println!(
                    "strawwu-app-registry: dry-run remove {} via desktop ({})",
                    preview.id, preview.name
                );
            } else {
                println!(
                    "strawwu-app-registry: removed {} via desktop ({})",
                    preview.id, preview.name
                );
            }
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: remove-by-desktop failed: {e}");
            Err(exit_code(&e))
        }
    }
}

fn cmd_validate(path: Option<PathBuf>) -> Result<(), i32> {
    let path = path.unwrap_or_else(default_registry_path);
    if !path.exists() {
        eprintln!(
            "strawwu-app-registry: validate failed: {} not found",
            path.display()
        );
        return Err(1);
    }
    match load_registry_file(&path) {
        Ok(registry) => {
            println!(
                "strawwu-app-registry: valid (schema {}, {} apps)",
                registry.schema_version,
                registry.apps.len()
            );
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: validate failed: {e}");
            Err(exit_code(&e))
        }
    }
}

fn cmd_scan(linux: bool, flatpak: bool, dry_run: bool, json: bool) -> Result<(), i32> {
    let mut options = ScanOptions::default();
    options.linux = linux;
    options.flatpak = flatpak;
    if linux {
        options.linux_dirs = strawwu_app_registry::scan::default_linux_desktop_dirs();
    }
    options.flatpak_list_file = std::env::var("STRAWWU_FLATPAK_LIST_FILE")
        .ok()
        .map(PathBuf::from);

    let discovered = strawwu_app_registry::scan_apps(&options);
    let mut store = open_store()?;
    let mut results = Vec::new();
    let mut counts = std::collections::HashMap::new();

    for app in &discovered {
        let action = store
            .upsert_from_scan(app, dry_run)
            .map_err(|e| {
                eprintln!("strawwu-app-registry: scan failed for {}: {e}", app.id);
                exit_code(&e)
            })?;
        *counts.entry(format!("{:?}", action)).or_insert(0usize) += 1;
        results.push(serde_json::json!({
            "id": app.id,
            "name": app.name,
            "kind": app.kind,
            "source": app.source,
            "action": action,
        }));
    }

    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "dry_run": dry_run,
                "linux": linux,
                "flatpak": flatpak,
                "discovered": discovered.len(),
                "counts": counts,
                "results": results,
            }))
            .unwrap()
        );
    } else {
        let prefix = if dry_run { "dry-run " } else { "" };
        println!(
            "strawwu-app-registry: {prefix}scan complete ({} discovered)",
            discovered.len()
        );
        for (action, count) in &counts {
            println!("  {action}: {count}");
        }
    }
    Ok(())
}

fn open_store() -> Result<RegistryStore, i32> {
    RegistryStore::open().map_err(|e| {
        eprintln!("strawwu-app-registry: {e}");
        exit_code(&e)
    })
}

fn exit_code(err: &RegistryError) -> i32 {
    match err {
        RegistryError::Protected(_) => 2,
        RegistryError::NotFound(_) => 1,
        RegistryError::Duplicate(_) => 1,
        RegistryError::Validation(_) => 1,
        RegistryError::Io(_) | RegistryError::Json(_) => 1,
    }
}

fn print_help() {
    println!(
        "strawwu-app-registry {VERSION} — StrawWU user app registry

USAGE:
    strawwu-app-registry <COMMAND> [OPTIONS]

COMMANDS:
    list [--json]                     List registered apps
    show <id> [--json]                Show one app entry
    register --id <id> --name <name> [--kind win32|linux|flatpak|native]
             [--source installer|launcher|flatpak|seed|manual]
             [--install-path <path>] [--desktop-entry <path>] [--protected]
             [--backend native|container|microvm]
    remove <id> [--dry-run] [--json]  Mark app removed (protected apps rejected)
    remove-by-desktop <path> [--dry-run] [--json]
                                      Resolve app from .desktop path and mark removed
    validate [path]                   Validate registry JSON (default: /var/lib/strawwu/app-registry.json)
    scan [--linux] [--flatpak] [--all] [--dry-run] [--json]
                                      Scan Linux .desktop / Flatpak apps into registry
    version                           Show version
    help                              Show this help

ENV:
    STRAWWU_APP_REGISTRY      Override registry JSON path
    STRAWWU_APP_REGISTRY_LOG  Override log path (/var/log/strawwu/app-registry.log)
"
    );
}
