use std::path::PathBuf;
use std::process;

use strawwu_app_registry::cli::{self, Command};
use strawwu_app_registry::{
    default_registry_path, load_registry_file, RegistryError, RegistryStore, ScanOptions,
};

const VERSION: &str = env!("CARGO_PKG_VERSION");

// Restore the default SIGPIPE disposition so the CLI is terminated by the signal
// (like every other Unix filter) when a downstream reader closes the pipe early
// — e.g. `strawwu-app-registry ... | head` or `| grep -q`. Rust ignores SIGPIPE
// by default and instead panics on the failed stdout write ("Broken pipe"), which
// is noisy and breaks pipelines. Must run before any stdout output.
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
        Command::Remove { id, dry_run, deep, json } => {
            if deep {
                cmd_deep_remove(&id, dry_run, json)
            } else {
                cmd_remove(&id, dry_run, json)
            }
        }
        Command::DeepRemove { id, dry_run, json } => cmd_deep_remove(&id, dry_run, json),
        Command::RemoveByDesktop {
            desktop,
            dry_run,
            deep,
            json,
        } => {
            if deep {
                cmd_deep_remove_by_desktop(&desktop, dry_run, json)
            } else {
                cmd_remove_by_desktop(&desktop, dry_run, json)
            }
        }
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

fn cmd_deep_remove(id: &str, dry_run: bool, json: bool) -> Result<(), i32> {
    let mut store = open_store()?;
    match store.deep_remove(id, dry_run) {
        Ok(result) => {
            if json {
                println!("{}", serde_json::to_string_pretty(&result).unwrap());
            } else if dry_run {
                println!(
                    "strawwu-app-registry: dry-run deep-remove {id} ({})",
                    result.preview.name
                );
                for path in &result.paths_deleted {
                    println!("  would delete: {path}");
                }
                for skip in &result.paths_skipped {
                    println!("  skip {}: {}", skip.path, skip.reason);
                }
            } else {
                println!(
                    "strawwu-app-registry: deep-removed {id} ({})",
                    result.preview.name
                );
                for path in &result.paths_deleted {
                    println!("  deleted: {path}");
                }
            }
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: deep-remove failed: {e}");
            Err(exit_code(&e))
        }
    }
}

fn cmd_deep_remove_by_desktop(desktop: &str, dry_run: bool, json: bool) -> Result<(), i32> {
    let mut store = open_store()?;
    match store.deep_remove_by_desktop(desktop, dry_run) {
        Ok(result) => {
            if json {
                println!("{}", serde_json::to_string_pretty(&result).unwrap());
            } else if dry_run {
                println!(
                    "strawwu-app-registry: dry-run deep-remove {} via desktop ({})",
                    result.preview.id, result.preview.name
                );
            } else {
                println!(
                    "strawwu-app-registry: deep-removed {} via desktop ({})",
                    result.preview.id, result.preview.name
                );
            }
            Ok(())
        }
        Err(e) => {
            eprintln!("strawwu-app-registry: deep-remove-by-desktop failed: {e}");
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
    let discovered_ids: std::collections::HashSet<String> =
        discovered.iter().map(|app| app.id.clone()).collect();
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

    let removed = store
        .sync_removed_from_scan(&discovered_ids, dry_run)
        .map_err(|e| {
            eprintln!("strawwu-app-registry: scan-remove sync failed: {e}");
            exit_code(&e)
        })?;
    let removed_count = removed.len();

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
                "removed": removed,
                "removed_count": removed_count,
            }))
            .unwrap()
        );
    } else {
        let prefix = if dry_run { "dry-run " } else { "" };
        println!(
            "strawwu-app-registry: {prefix}scan complete ({} discovered, {removed_count} removed)",
            discovered.len()
        );
        for (action, count) in &counts {
            println!("  {action}: {count}");
        }
        if removed_count > 0 {
            println!("  scan-remove synced: {removed_count}");
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
        RegistryError::DeepRemove(_) => 1,
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
    remove <id> [--deep] [--dry-run] [--json]
                                      Mark app removed; --deep deletes allowlisted paths first
    deep-remove <id> [--dry-run] [--json]
                                      Delete allowlisted install paths + flatpak uninstall, then mark removed
    remove-by-desktop <path> [--deep] [--dry-run] [--json]
                                      Resolve app from .desktop path and remove (optional --deep)
    validate [path]                   Validate registry JSON (default: /var/lib/strawwu/app-registry.json)
    scan [--linux] [--flatpak] [--all] [--dry-run] [--json]
                                      Scan Linux .desktop / Flatpak apps into registry
    version                           Show version
    help                              Show this help

ENV:
    STRAWWU_APP_REGISTRY      Override registry JSON path
    STRAWWU_APP_REGISTRY_LOG  Override log path (/var/log/strawwu/app-registry.log)
    STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES  Extra colon-separated deletable path prefixes (tests/dev)
    STRAWWU_SKIP_FLATPAK_UNINSTALL      Skip flatpak uninstall during deep-remove
"
    );
}
