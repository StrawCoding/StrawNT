use std::path::Path;

use strawwu_app_registry::{
    default_registry_path, AppKind, ExecutionBackend, RegistryError, RegistryStore,
};

use crate::detect::BinaryFormat;

pub fn derive_app_id(binary: &Path) -> String {
    let stem = binary
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("app");
    slugify(stem)
}

pub fn derive_app_name(binary: &Path) -> String {
    binary
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("App")
        .to_string()
}

fn slugify(input: &str) -> String {
    let lower = input.to_lowercase();
    let mut slug = String::new();
    let mut started = false;

    for ch in lower.chars() {
        if ch.is_ascii_alphanumeric() || ch == '.' || ch == '_' || ch == '-' {
            if !started && ch.is_ascii_alphanumeric() {
                started = true;
            }
            if started {
                slug.push(ch);
            }
        } else if started && !slug.ends_with('-') {
            slug.push('-');
        }
    }

    let trimmed = slug.trim_matches('-').chars().take(64).collect::<String>();
    if trimmed.is_empty() || !trimmed.chars().next().unwrap().is_ascii_alphanumeric() {
        "app".to_string()
    } else {
        trimmed
    }
}

fn kind_for_format(format: BinaryFormat) -> AppKind {
    match format {
        BinaryFormat::PE => AppKind::Win32,
        BinaryFormat::ELF => AppKind::Linux,
        BinaryFormat::Unknown => AppKind::Native,
    }
}

fn backend_from_str(backend: Option<&str>) -> Option<ExecutionBackend> {
    backend.and_then(|value| match value {
        "native" => Some(ExecutionBackend::Native),
        "container" => Some(ExecutionBackend::Container),
        "microvm" => Some(ExecutionBackend::Microvm),
        _ => None,
    })
}

fn install_path_for(binary: &Path) -> Option<String> {
    binary
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .map(|p| p.to_string_lossy().into_owned())
}

pub fn register_launch(
    binary: &Path,
    format: BinaryFormat,
    backend: Option<&str>,
    desktop_entry: Option<String>,
) -> Result<String, RegistryError> {
    let id = derive_app_id(binary);
    let name = derive_app_name(binary);
    let kind = kind_for_format(format);
    let install_path = install_path_for(binary);
    let backend = backend_from_str(backend);

    let mut store = RegistryStore::open_at(default_registry_path())?;
    store.upsert_from_launch(&id, &name, kind, install_path, backend, desktop_entry)?;
    Ok(id)
}

pub fn register_install(installer: &Path) -> Result<String, RegistryError> {
    let id = derive_app_id(installer);
    let name = derive_app_name(installer);
    let installer_path = Some(installer.to_string_lossy().into_owned());

    let mut store = RegistryStore::open_at(default_registry_path())?;
    store.upsert_from_install(&id, &name, installer_path)?;
    Ok(id)
}

fn kind_label(kind: AppKind) -> &'static str {
    match kind {
        AppKind::Win32 => "win32",
        AppKind::Linux => "linux",
        AppKind::Flatpak => "flatpak",
        AppKind::Native => "native",
    }
}

pub fn list_registered_apps() -> Result<Vec<(String, String, String)>, RegistryError> {
    let store = RegistryStore::open_at(default_registry_path())?;
    Ok(store
        .list_active()
        .iter()
        .map(|app| {
            (
                app.id.clone(),
                app.name.clone(),
                kind_label(app.kind).to_string(),
            )
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::sync::Mutex;
    use tempfile::tempdir;

    static REGISTRY_ENV: Mutex<()> = Mutex::new(());

    struct RegistryEnvGuard {
        _lock: std::sync::MutexGuard<'static, ()>,
        saved_registry: Option<String>,
        saved_log: Option<String>,
    }

    impl RegistryEnvGuard {
        fn new(registry: &Path, log: &Path) -> Self {
            let lock = REGISTRY_ENV.lock().unwrap_or_else(|e| e.into_inner());
            let saved_registry = env::var("STRAWWU_APP_REGISTRY").ok();
            let saved_log = env::var("STRAWWU_APP_REGISTRY_LOG").ok();
            env::set_var(
                "STRAWWU_APP_REGISTRY",
                registry.to_string_lossy().as_ref(),
            );
            env::set_var(
                "STRAWWU_APP_REGISTRY_LOG",
                log.to_string_lossy().as_ref(),
            );
            Self {
                _lock: lock,
                saved_registry,
                saved_log,
            }
        }
    }

    impl Drop for RegistryEnvGuard {
        fn drop(&mut self) {
            restore_env("STRAWWU_APP_REGISTRY", self.saved_registry.as_deref());
            restore_env("STRAWWU_APP_REGISTRY_LOG", self.saved_log.as_deref());
        }
    }

    fn restore_env(key: &str, value: Option<&str>) {
        match value {
            Some(v) => env::set_var(key, v),
            None => env::remove_var(key),
        }
    }

    #[test]
    fn derive_app_id_from_exe() {
        assert_eq!(derive_app_id(Path::new("/opt/games/My Game.exe")), "my-game");
        assert_eq!(derive_app_id(Path::new("notepad.exe")), "notepad");
    }

    #[test]
    fn derive_app_id_sanitizes_invalid_prefix() {
        assert_eq!(derive_app_id(Path::new("!!!.exe")), "app");
    }

    #[test]
    fn register_launch_writes_registry() {
        let dir = tempdir().unwrap();
        let registry = dir.path().join("app-registry.json");
        let log = dir.path().join("registry.log");
        let _env = RegistryEnvGuard::new(&registry, &log);

        let binary = dir.path().join("demo-app.exe");
        let id = register_launch(&binary, BinaryFormat::PE, Some("native"), None).unwrap();
        assert_eq!(id, "demo-app");

        // Drop each store handle before reopening: the registry holds an
        // exclusive advisory lock for its lifetime, so overlapping handles on the
        // same path in one process would contend.
        {
            let store = RegistryStore::open_at(registry.clone()).unwrap();
            let app = store.get("demo-app").expect("registered");
            assert_eq!(app.name, "demo-app");
            assert_eq!(app.kind, AppKind::Win32);
            assert_eq!(app.source, strawwu_app_registry::AppSource::Launcher);
        }

        let id2 = register_launch(&binary, BinaryFormat::PE, Some("container"), None).unwrap();
        assert_eq!(id2, "demo-app");
        let store = RegistryStore::open_at(registry).unwrap();
        let app = store.get("demo-app").expect("upserted");
        assert_eq!(
            app.execution_backend,
            Some(ExecutionBackend::Container)
        );
    }

    #[test]
    fn register_install_pending_state() {
        let dir = tempdir().unwrap();
        let registry = dir.path().join("app-registry.json");
        let log = dir.path().join("registry.log");
        let _env = RegistryEnvGuard::new(&registry, &log);

        let installer = dir.path().join("setup.exe");
        let id = register_install(&installer).unwrap();
        assert_eq!(id, "setup");

        let store = RegistryStore::open_at(registry).unwrap();
        let app = store.get("setup").expect("registered");
        assert_eq!(
            app.install_state,
            strawwu_app_registry::InstallState::Pending
        );
    }
}
