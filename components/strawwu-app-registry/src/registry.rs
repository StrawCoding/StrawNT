use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::entry::{AppEntry, AppKind, AppRegistryFile, AppSource, ExecutionBackend, InstallState};
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
}

impl RegistryStore {
    pub fn open() -> Result<Self, RegistryError> {
        Self::open_at(default_registry_path())
    }

    pub fn open_at(path: PathBuf) -> Result<Self, RegistryError> {
        let log_path = default_log_path();
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
        protected: bool,
        backend: Option<ExecutionBackend>,
    ) -> Result<&AppEntry, RegistryError> {
        let mut entry = AppEntry::new(id, name, kind, source);
        entry.install_path = install_path;
        entry.protected = protected;
        entry.execution_backend = backend.or(Some(ExecutionBackend::Native));
        self.register(entry)?;
        Ok(self.data.find(id).expect("just inserted"))
    }

    /// Register or refresh an app launched via `strawwu run` (W4-W1).
    pub fn upsert_from_launch(
        &mut self,
        id: &str,
        name: &str,
        kind: AppKind,
        install_path: Option<String>,
        backend: Option<ExecutionBackend>,
    ) -> Result<&AppEntry, RegistryError> {
        if let Some(app) = self.data.find_mut(id) {
            app.name = name.to_string();
            app.kind = kind;
            app.source = AppSource::Launcher;
            app.install_state = InstallState::Installed;
            app.install_path = install_path;
            app.execution_backend = backend.or(Some(ExecutionBackend::Native));
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
            false,
            backend,
        )
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

    pub fn flush(&self) -> Result<(), RegistryError> {
        validate_registry(&self.data)
            .map_err(|errs| RegistryError::Validation(errs.join("; ")))?;
        ensure_parent_dir(&self.path)?;
        let json = serde_json::to_string_pretty(&self.data)?;
        fs::write(&self.path, format!("{json}\n"))?;
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
        let line = format!(
            "{{\"ts\":\"{}\",\"component\":\"app-registry\",\"action\":\"{action}\",\"app_id\":\"{app_id}\"}}\n",
            chrono::Utc::now().to_rfc3339()
        );
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
            )
            .unwrap();
        store
            .upsert_from_launch(
                "demo-app",
                "Demo App Updated",
                AppKind::Win32,
                Some("/opt/demo2".into()),
                Some(ExecutionBackend::Container),
            )
            .unwrap();

        let app = store.get("demo-app").expect("app");
        assert_eq!(app.name, "Demo App Updated");
        assert_eq!(app.install_path.as_deref(), Some("/opt/demo2"));
        assert_eq!(app.source, AppSource::Launcher);
        assert_eq!(app.execution_backend, Some(ExecutionBackend::Container));
    }
}
