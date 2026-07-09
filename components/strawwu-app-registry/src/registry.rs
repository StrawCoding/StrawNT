use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use thiserror::Error;

/// Cross-process advisory lock held for the whole open→mutate→flush lifetime of a
/// [`RegistryStore`] so concurrent writers (launcher, registry CLI, install hooks)
/// serialize instead of racing the read-modify-write window and clobbering each
/// other. The lock is released when the file handle is dropped.
struct RegistryLock {
    #[allow(dead_code)]
    file: fs::File,
}

impl RegistryLock {
    #[cfg(unix)]
    fn acquire(registry_path: &Path) -> Result<Self, std::io::Error> {
        use std::os::unix::io::AsRawFd;
        let lock_path = lock_path_for(registry_path);
        if let Some(parent) = lock_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let file = fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(&lock_path)?;
        // Non-blocking retry with a bounded timeout instead of a blocking
        // LOCK_EX: a stale/held lock surfaces as a clean error rather than an
        // indefinite hang. Override the budget with STRAWWU_REGISTRY_LOCK_TIMEOUT_MS.
        let timeout_ms: u64 = std::env::var("STRAWWU_REGISTRY_LOCK_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(10_000);
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms);
        loop {
            let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if rc == 0 {
                return Ok(Self { file });
            }
            let err = std::io::Error::last_os_error();
            let would_block = matches!(
                err.raw_os_error(),
                Some(code) if code == libc::EWOULDBLOCK || code == libc::EAGAIN
            );
            if !would_block {
                return Err(err);
            }
            if std::time::Instant::now() >= deadline {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::WouldBlock,
                    format!(
                        "timed out acquiring registry lock: {}",
                        lock_path.display()
                    ),
                ));
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
    }

    #[cfg(not(unix))]
    fn acquire(registry_path: &Path) -> Result<Self, std::io::Error> {
        let lock_path = lock_path_for(registry_path);
        if let Some(parent) = lock_path.parent() {
            fs::create_dir_all(parent)?;
        }
        let file = fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(&lock_path)?;
        Ok(Self { file })
    }
}

fn lock_path_for(registry_path: &Path) -> PathBuf {
    let mut name = registry_path
        .file_name()
        .map(|n| n.to_os_string())
        .unwrap_or_default();
    name.push(".lock");
    registry_path.with_file_name(name)
}

use crate::deep_remove::{
    execute_deep_remove_plan, plan_deep_remove, should_sync_remove_on_scan, DeepRemoveResult,
};
use crate::desktop::{find_by_desktop, slug_from_desktop_basename};
use crate::entry::{AppEntry, AppKind, AppRegistryFile, AppSource, ExecutionBackend, InstallState};
use crate::scan::ScannedApp;
use crate::paths::{default_log_path, default_registry_path, ensure_parent_dir};
use crate::validate::validate_registry;

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("validation failed: {0}")]
    Validation(String),
    #[error("app not found: {0}")]
    NotFound(String),
    #[error("app is protected: {0}")]
    Protected(String),
    #[error("app already exists: {0}")]
    Duplicate(String),
    #[error("deep remove failed: {0}")]
    DeepRemove(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ScanUpsertAction {
    Added,
    Updated,
    Reactivated,
    Skipped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum ScanRemoveAction {
    Removed,
    Skipped,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ScanRemoveResult {
    pub id: String,
    pub name: String,
    pub action: ScanRemoveAction,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RemovePreview {
    pub id: String,
    pub name: String,
    pub install_path: Option<String>,
    pub desktop_entry: Option<String>,
    pub protected: bool,
}

pub struct RegistryStore {
    path: PathBuf,
    log_path: PathBuf,
    data: AppRegistryFile,
    // Held for the store's lifetime to serialize concurrent writers.
    _lock: RegistryLock,
}

impl RegistryStore {
    pub fn open() -> Result<Self, RegistryError> {
        Self::open_at(default_registry_path())
    }

    pub fn open_at(path: PathBuf) -> Result<Self, RegistryError> {
        let log_path = default_log_path();
        ensure_parent_dir(&path)?;
        // Acquire the cross-process lock BEFORE reading so the whole
        // read-modify-write cycle is serialized against other writers.
        let lock = RegistryLock::acquire(&path)?;
        let data = if path.exists() {
            let raw = fs::read_to_string(&path)?;
            let registry: AppRegistryFile = serde_json::from_str(&raw)?;
            validate_registry(&registry)
                .map_err(|errs| RegistryError::Validation(errs.join("; ")))?;
            registry
        } else {
            AppRegistryFile::default()
        };

        Ok(Self {
            path,
            log_path,
            data,
            _lock: lock,
        })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn data(&self) -> &AppRegistryFile {
        &self.data
    }

    pub fn list_active(&self) -> Vec<&AppEntry> {
        self.data.active_apps()
    }

    pub fn get(&self, id: &str) -> Option<&AppEntry> {
        self.data.find(id)
    }

    pub fn register(&mut self, entry: AppEntry) -> Result<(), RegistryError> {
        if self.data.find(&entry.id).is_some() {
            return Err(RegistryError::Duplicate(entry.id));
        }
        validate_registry(&AppRegistryFile {
            schema_version: self.data.schema_version.clone(),
            updated_at: self.data.updated_at.clone(),
            apps: {
                let mut apps = self.data.apps.clone();
                apps.push(entry.clone());
                apps
            },
        })
        .map_err(|errs| RegistryError::Validation(errs.join("; ")))?;

        self.data.apps.push(entry);
        self.data.touch();
        self.flush()?;
        self.log_event("register", &self.data.apps.last().unwrap().id);
        Ok(())
    }

    pub fn register_new(
        &mut self,
        id: &str,
        name: &str,
        kind: AppKind,
        source: AppSource,
        install_path: Option<String>,
        desktop_entry: Option<String>,
        protected: bool,
        backend: Option<ExecutionBackend>,
    ) -> Result<&AppEntry, RegistryError> {
        let mut entry = AppEntry::new(id, name, kind, source);
        entry.install_path = install_path;
        entry.desktop_entry = desktop_entry;
        entry.protected = protected;
        entry.execution_backend = backend.or(Some(ExecutionBackend::Native));
        self.register(entry)?;
        Ok(self.data.find(id).expect("just inserted"))
    }

    pub fn find_by_desktop_path(&self, raw: &str) -> Option<&AppEntry> {
        find_by_desktop(&self.data, raw)
    }

    pub fn resolve_id_for_desktop(&self, raw: &str) -> Option<String> {
        if let Some(app) = self.find_by_desktop_path(raw) {
            return Some(app.id.clone());
        }
        slug_from_desktop_basename(std::path::Path::new(raw))
    }

    pub fn remove_by_desktop(&mut self, raw: &str, dry_run: bool) -> Result<RemovePreview, RegistryError> {
        let id = self
            .resolve_id_for_desktop(raw)
            .ok_or_else(|| RegistryError::NotFound(raw.to_string()))?;
        self.remove(&id, dry_run)
    }

    /// Register or refresh an app launched via `strawwu run` (W4-W1).
    pub fn upsert_from_launch(
        &mut self,
        id: &str,
        name: &str,
        kind: AppKind,
        install_path: Option<String>,
        backend: Option<ExecutionBackend>,
        desktop_entry: Option<String>,
    ) -> Result<&AppEntry, RegistryError> {
        if let Some(app) = self.data.find_mut(id) {
            app.name = name.to_string();
            app.kind = kind;
            app.source = AppSource::Launcher;
            app.install_state = InstallState::Installed;
            app.install_path = install_path;
            app.execution_backend = backend.or(Some(ExecutionBackend::Native));
            if desktop_entry.is_some() {
                app.desktop_entry = desktop_entry;
            }
            app.touch();
            self.data.touch();
            self.flush()?;
            self.log_event("upsert", id);
            return Ok(self.data.find(id).expect("just updated"));
        }

        self.register_new(
            id,
            name,
            kind,
            AppSource::Launcher,
            install_path,
            desktop_entry,
            false,
            backend,
        )
    }

    /// Skip scan upsert for launcher-tracked or protected Windows installer entries.
    pub fn should_skip_scan_upsert(app: &AppEntry) -> bool {
        if app.protected {
            return true;
        }
        if app.source == AppSource::Launcher {
            return true;
        }
        app.source == AppSource::Installer && app.kind == AppKind::Win32
    }

    /// Register or refresh an app discovered by Linux/Flatpak install hooks (W5-R4).
    pub fn upsert_from_scan(
        &mut self,
        scanned: &ScannedApp,
        dry_run: bool,
    ) -> Result<ScanUpsertAction, RegistryError> {
        if let Some(app) = self.data.find(&scanned.id) {
            if Self::should_skip_scan_upsert(app) {
                return Ok(ScanUpsertAction::Skipped);
            }
            let action = if app.install_state == InstallState::Removed {
                ScanUpsertAction::Reactivated
            } else {
                ScanUpsertAction::Updated
            };
            if dry_run {
                return Ok(action);
            }
            if let Some(app) = self.data.find_mut(&scanned.id) {
                app.name = scanned.name.clone();
                app.kind = scanned.kind;
                app.source = scanned.source;
                app.install_state = InstallState::Installed;
                app.install_path = scanned.install_path.clone();
                app.desktop_entry = scanned.desktop_entry.clone();
                app.execution_backend = Some(ExecutionBackend::Native);
                app.touch();
            }
            self.data.touch();
            self.flush()?;
            self.log_event("scan-upsert", &scanned.id);
            return Ok(action);
        }

        if dry_run {
            return Ok(ScanUpsertAction::Added);
        }

        self.register_new(
            &scanned.id,
            &scanned.name,
            scanned.kind,
            scanned.source,
            scanned.install_path.clone(),
            scanned.desktop_entry.clone(),
            false,
            Some(ExecutionBackend::Native),
        )?;
        self.log_event("scan-register", &scanned.id);
        Ok(ScanUpsertAction::Added)
    }

    /// Record a pending install initiated via `strawwu install` (W4-W1 stub).
    pub fn upsert_from_install(
        &mut self,
        id: &str,
        name: &str,
        installer_path: Option<String>,
    ) -> Result<&AppEntry, RegistryError> {
        if let Some(app) = self.data.find_mut(id) {
            app.name = name.to_string();
            app.kind = AppKind::Win32;
            app.source = AppSource::Installer;
            app.install_state = InstallState::Pending;
            app.install_path = installer_path;
            app.execution_backend = Some(ExecutionBackend::Native);
            app.touch();
            self.data.touch();
            self.flush()?;
            self.log_event("install-pending", id);
            return Ok(self.data.find(id).expect("just updated"));
        }

        let mut entry = AppEntry::new(id, name, AppKind::Win32, AppSource::Installer);
        entry.install_state = InstallState::Pending;
        entry.install_path = installer_path;
        entry.execution_backend = Some(ExecutionBackend::Native);
        self.register(entry)?;
        Ok(self.data.find(id).expect("just inserted"))
    }

    pub fn preview_remove(&self, id: &str) -> Result<RemovePreview, RegistryError> {
        let app = self
            .data
            .find(id)
            .ok_or_else(|| RegistryError::NotFound(id.to_string()))?;
        Ok(RemovePreview {
            id: app.id.clone(),
            name: app.name.clone(),
            install_path: app.install_path.clone(),
            desktop_entry: app.desktop_entry.clone(),
            protected: app.protected,
        })
    }

    pub fn remove(&mut self, id: &str, dry_run: bool) -> Result<RemovePreview, RegistryError> {
        let preview = self.preview_remove(id)?;
        if preview.protected {
            return Err(RegistryError::Protected(id.to_string()));
        }
        if dry_run {
            self.log_event("remove-dry-run", id);
            return Ok(preview);
        }

        if let Some(app) = self.data.find_mut(id) {
            app.install_state = InstallState::Removed;
            app.touch();
        }
        self.data.touch();
        self.flush()?;
        self.log_event("remove", id);
        Ok(preview)
    }

    /// Deep remove: delete allowlisted install/desktop paths, optional flatpak uninstall, then mark removed.
    pub fn deep_remove(&mut self, id: &str, dry_run: bool) -> Result<DeepRemoveResult, RegistryError> {
        let preview = self.preview_remove(id)?;
        if preview.protected {
            return Err(RegistryError::Protected(id.to_string()));
        }

        let app = self
            .data
            .find(id)
            .ok_or_else(|| RegistryError::NotFound(id.to_string()))?;
        let plan = plan_deep_remove(app);
        let paths_skipped = plan.paths_skipped.clone();

        if dry_run {
            let (paths_deleted, flatpak) = execute_deep_remove_plan(&plan, true)
                .map_err(|e| RegistryError::DeepRemove(e.to_string()))?;
            self.log_event("deep-remove-dry-run", id);
            return Ok(DeepRemoveResult {
                preview,
                dry_run: true,
                registry_removed: false,
                paths_deleted,
                paths_skipped,
                flatpak,
            });
        }

        let (paths_deleted, flatpak) = execute_deep_remove_plan(&plan, false)
            .map_err(|e| RegistryError::DeepRemove(e.to_string()))?;

        if let Some(app) = self.data.find_mut(id) {
            app.install_state = InstallState::Removed;
            app.touch();
        }
        self.data.touch();
        self.flush()?;
        self.log_event("deep-remove", id);

        Ok(DeepRemoveResult {
            preview,
            dry_run: false,
            registry_removed: true,
            paths_deleted,
            paths_skipped,
            flatpak,
        })
    }

    pub fn deep_remove_by_desktop(
        &mut self,
        raw: &str,
        dry_run: bool,
    ) -> Result<DeepRemoveResult, RegistryError> {
        let id = self
            .resolve_id_for_desktop(raw)
            .ok_or_else(|| RegistryError::NotFound(raw.to_string()))?;
        self.deep_remove(&id, dry_run)
    }

    /// Mark scan-managed apps removed when they disappear from Linux/Flatpak discovery.
    pub fn sync_removed_from_scan(
        &mut self,
        discovered_ids: &HashSet<String>,
        dry_run: bool,
    ) -> Result<Vec<ScanRemoveResult>, RegistryError> {
        let candidates: Vec<(String, String)> = self
            .data
            .active_apps()
            .iter()
            .filter(|app| should_sync_remove_on_scan(app))
            .filter(|app| !discovered_ids.contains(&app.id))
            .map(|app| (app.id.clone(), app.name.clone()))
            .collect();

        let mut results = Vec::new();
        for (id, name) in candidates {
            if dry_run {
                self.log_event("scan-remove-dry-run", &id);
                results.push(ScanRemoveResult {
                    id: id.clone(),
                    name,
                    action: ScanRemoveAction::Removed,
                });
                continue;
            }
            self.remove(&id, false)?;
            self.log_event("scan-remove", &id);
            results.push(ScanRemoveResult {
                id,
                name,
                action: ScanRemoveAction::Removed,
            });
        }
        Ok(results)
    }

    pub fn flush(&self) -> Result<(), RegistryError> {
        validate_registry(&self.data)
            .map_err(|errs| RegistryError::Validation(errs.join("; ")))?;
        ensure_parent_dir(&self.path)?;
        let json = serde_json::to_string_pretty(&self.data)?;
        // Atomic replace: write to a sibling temp file, fsync, then rename over
        // the target so a crash mid-write never leaves a truncated/corrupt
        // registry. rename(2) is atomic within the same filesystem.
        let mut tmp = self.path.clone();
        let mut tmp_name = tmp
            .file_name()
            .map(|n| n.to_os_string())
            .unwrap_or_default();
        tmp_name.push(format!(".tmp.{}", std::process::id()));
        tmp.set_file_name(tmp_name);

        {
            let mut f = fs::File::create(&tmp)?;
            f.write_all(json.as_bytes())?;
            f.write_all(b"\n")?;
            f.sync_all()?;
        }
        if let Err(e) = fs::rename(&tmp, &self.path) {
            let _ = fs::remove_file(&tmp);
            return Err(e.into());
        }
        Ok(())
    }

    fn log_event(&self, action: &str, app_id: &str) {
        if let Ok(()) = self.try_log(action, app_id) {
            return;
        }
        // Logging is best-effort; registry writes must not fail because /var/log is absent.
    }

    fn try_log(&self, action: &str, app_id: &str) -> Result<(), RegistryError> {
        ensure_parent_dir(&self.log_path)?;
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log_path)?;
        // Build the log line with serde so an app_id containing quotes/newlines
        // (it derives from user-controlled paths/desktop names) cannot inject or
        // break the JSONL structure.
        let mut line = serde_json::to_string(&serde_json::json!({
            "ts": chrono::Utc::now().to_rfc3339(),
            "component": "app-registry",
            "action": action,
            "app_id": app_id,
        }))?;
        line.push('\n');
        file.write_all(line.as_bytes())?;
        Ok(())
    }
}

pub fn load_registry_file(path: &Path) -> Result<AppRegistryFile, RegistryError> {
    let raw = fs::read_to_string(path)?;
    let registry: AppRegistryFile = serde_json::from_str(&raw)?;
    validate_registry(&registry).map_err(|errs| RegistryError::Validation(errs.join("; ")))?;
    Ok(registry)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::ScannedApp;
    use std::collections::HashSet;
    use tempfile::tempdir;

    #[test]
    fn register_list_remove_roundtrip() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        std::env::set_var(
            "STRAWWU_APP_REGISTRY_LOG",
            dir.path().join("registry.log").to_string_lossy().as_ref(),
        );

        let mut store = RegistryStore::open_at(path).unwrap();
        assert!(store.list_active().is_empty());

        store
            .register_new(
                "demo-app",
                "Demo App",
                AppKind::Win32,
                AppSource::Installer,
                Some("/opt/strawwu/apps/demo".into()),
                None,
                false,
                None,
            )
            .unwrap();
        assert_eq!(store.list_active().len(), 1);

        let preview = store.remove("demo-app", true).unwrap();
        assert_eq!(preview.id, "demo-app");
        assert_eq!(store.list_active().len(), 1);

        store.remove("demo-app", false).unwrap();
        assert!(store.list_active().is_empty());
        assert!(store.path().exists());
    }

    #[test]
    fn protected_app_cannot_be_removed() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .register_new(
                "system-app",
                "System",
                AppKind::Native,
                AppSource::Seed,
                None,
                None,
                true,
                None,
            )
            .unwrap();
        let err = store.remove("system-app", false).unwrap_err();
        assert!(matches!(err, RegistryError::Protected(_)));
    }

    #[test]
    fn upsert_from_launch_updates_existing() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        std::env::set_var(
            "STRAWWU_APP_REGISTRY_LOG",
            dir.path().join("registry.log").to_string_lossy().as_ref(),
        );
        let mut store = RegistryStore::open_at(path.clone()).unwrap();

        store
            .upsert_from_launch(
                "demo-app",
                "Demo App",
                AppKind::Win32,
                Some("/opt/demo".into()),
                None,
                None,
            )
            .unwrap();
        store
            .upsert_from_launch(
                "demo-app",
                "Demo App Updated",
                AppKind::Win32,
                Some("/opt/demo2".into()),
                Some(ExecutionBackend::Container),
                None,
            )
            .unwrap();

        let app = store.get("demo-app").expect("app");
        assert_eq!(app.name, "Demo App Updated");
        assert_eq!(app.install_path.as_deref(), Some("/opt/demo2"));
        assert_eq!(app.source, AppSource::Launcher);
        assert_eq!(app.execution_backend, Some(ExecutionBackend::Container));
    }

    #[test]
    fn remove_by_desktop_resolves_entry() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .register_new(
                "demo-app",
                "Demo App",
                AppKind::Win32,
                AppSource::Manual,
                None,
                Some("/tmp/demo-app.desktop".into()),
                false,
                None,
            )
            .unwrap();

        let preview = store.remove_by_desktop("/tmp/demo-app.desktop", true).unwrap();
        assert_eq!(preview.id, "demo-app");
        assert_eq!(store.list_active().len(), 1);

        store.remove_by_desktop("demo-app.desktop", false).unwrap();
        assert!(store.list_active().is_empty());
    }

    #[test]
    fn upsert_from_scan_skips_launcher_entries() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .upsert_from_launch(
                "demo-app",
                "Launcher Name",
                AppKind::Win32,
                Some("/opt/demo".into()),
                None,
                None,
            )
            .unwrap();

        let scanned = ScannedApp {
            id: "demo-app".into(),
            name: "Scanned Name".into(),
            kind: AppKind::Linux,
            source: AppSource::Manual,
            install_path: None,
            desktop_entry: None,
        };
        let action = store.upsert_from_scan(&scanned, false).unwrap();
        assert_eq!(action, ScanUpsertAction::Skipped);
        assert_eq!(store.get("demo-app").unwrap().name, "Launcher Name");
    }

    #[test]
    fn upsert_from_scan_registers_flatpak() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        let scanned = ScannedApp {
            id: "org.gnome.calculator".into(),
            name: "Calculator".into(),
            kind: AppKind::Flatpak,
            source: AppSource::Flatpak,
            install_path: Some("org.gnome.Calculator".into()),
            desktop_entry: None,
        };
        let action = store.upsert_from_scan(&scanned, false).unwrap();
        assert_eq!(action, ScanUpsertAction::Added);
        let app = store.get("org.gnome.calculator").unwrap();
        assert_eq!(app.kind, AppKind::Flatpak);
        assert_eq!(app.source, AppSource::Flatpak);
    }

    #[test]
    fn deep_remove_deletes_allowlisted_install_path() {
        let dir = tempdir().unwrap();
        let app_dir = dir.path().join("demo-app");
        std::fs::create_dir_all(&app_dir).unwrap();
        let path = dir.path().join("registry.json");
        std::env::set_var(
            "STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES",
            dir.path().to_string_lossy().as_ref(),
        );
        std::env::set_var(
            "STRAWWU_APP_REGISTRY_LOG",
            dir.path().join("registry.log").to_string_lossy().as_ref(),
        );

        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .register_new(
                "demo-app",
                "Demo",
                AppKind::Win32,
                AppSource::Installer,
                Some(app_dir.to_string_lossy().into_owned()),
                None,
                false,
                None,
            )
            .unwrap();

        std::env::set_var(
            "STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES",
            dir.path().to_string_lossy().as_ref(),
        );
        let result = store.deep_remove("demo-app", false).unwrap();
        assert!(result.registry_removed);
        assert!(!app_dir.exists());
        assert!(store.list_active().is_empty());
    }

    #[test]
    fn deep_remove_skips_forbidden_system_path() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .register_new(
                "system-linux",
                "System Linux",
                AppKind::Linux,
                AppSource::Manual,
                Some("/usr/bin/demo".into()),
                Some("/usr/share/applications/demo.desktop".into()),
                false,
                None,
            )
            .unwrap();

        let result = store.deep_remove("system-linux", false).unwrap();
        assert_eq!(result.paths_skipped.len(), 2);
        assert!(result.paths_deleted.is_empty());
        assert!(store.list_active().is_empty());
    }

    #[test]
    fn sync_removed_from_scan_marks_missing_flatpak() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .register_new(
                "org.gnome.calculator",
                "Calculator",
                AppKind::Flatpak,
                AppSource::Flatpak,
                Some("org.gnome.Calculator".into()),
                None,
                false,
                None,
            )
            .unwrap();

        let discovered = HashSet::from(["com.spotify.client".to_string()]);
        let removed = store.sync_removed_from_scan(&discovered, false).unwrap();
        assert_eq!(removed.len(), 1);
        assert_eq!(removed[0].id, "org.gnome.calculator");
        assert!(store.list_active().is_empty());
    }

    #[test]
    fn sync_removed_from_scan_skips_launcher_entries() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("registry.json");
        let mut store = RegistryStore::open_at(path).unwrap();
        store
            .upsert_from_launch(
                "demo-app",
                "Demo",
                AppKind::Win32,
                Some("/opt/demo".into()),
                None,
                None,
            )
            .unwrap();

        let removed = store.sync_removed_from_scan(&HashSet::new(), false).unwrap();
        assert!(removed.is_empty());
        assert_eq!(store.list_active().len(), 1);
    }
}
