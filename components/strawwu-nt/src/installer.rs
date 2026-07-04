use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::pe::PeMachine;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstallerType {
    Exe,
    Msi,
    Unknown,
}

impl InstallerType {
    pub fn detect(path: &str) -> Self {
        let lower = path.to_lowercase();
        if lower.ends_with(".msi") {
            Self::Msi
        } else if lower.ends_with(".exe") {
            Self::Exe
        } else {
            Self::Unknown
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstallState {
    Pending,
    Installing,
    Installed,
    Failed,
    Repaired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledApp {
    pub app_id: String,
    pub display_name: String,
    pub install_path: String,
    pub installer_type: InstallerType,
    pub state: InstallState,
    pub machine: String,
    pub files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileSnapshot {
    pub app_id: String,
    pub timestamp: String,
    pub registry_keys: HashMap<String, String>,
    pub file_list: Vec<String>,
    pub install_path: String,
}

impl ProfileSnapshot {
    pub fn capture(app: &InstalledApp) -> Self {
        Self {
            app_id: app.app_id.clone(),
            timestamp: "2026-07-04T00:00:00Z".to_string(),
            registry_keys: HashMap::new(),
            file_list: app.files.clone(),
            install_path: app.install_path.clone(),
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AppDatabase {
    apps: HashMap<String, InstalledApp>,
    snapshots: HashMap<String, ProfileSnapshot>,
}

impl AppDatabase {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn install(&mut self, app_id: &str, display_name: &str, path: &str, installer_type: InstallerType) -> &InstalledApp {
        let app = InstalledApp {
            app_id: app_id.to_string(),
            display_name: display_name.to_string(),
            install_path: path.to_string(),
            installer_type,
            state: InstallState::Installed,
            machine: PeMachine::Amd64.as_str().to_string(),
            files: vec![format!("{}/main.exe", path)],
        };
        self.apps.insert(app_id.to_string(), app);
        self.apps.get(app_id).unwrap()
    }

    pub fn get(&self, app_id: &str) -> Option<&InstalledApp> {
        self.apps.get(app_id)
    }

    pub fn list(&self) -> Vec<&InstalledApp> {
        self.apps.values().collect()
    }

    pub fn repair(&mut self, app_id: &str) -> Result<(), String> {
        if let Some(snap) = self.snapshots.get(app_id) {
            if let Some(app) = self.apps.get_mut(app_id) {
                app.files = snap.file_list.clone();
                app.state = InstallState::Repaired;
                return Ok(());
            }
        }
        if let Some(app) = self.apps.get_mut(app_id) {
            app.state = InstallState::Repaired;
            return Ok(());
        }
        Err(format!("app not found: {}", app_id))
    }

    pub fn snapshot(&mut self, app_id: &str) -> Result<(), String> {
        if let Some(app) = self.apps.get(app_id) {
            let snap = ProfileSnapshot::capture(app);
            self.snapshots.insert(app_id.to_string(), snap);
            Ok(())
        } else {
            Err(format!("app not found: {}", app_id))
        }
    }

    pub fn get_snapshot(&self, app_id: &str) -> Option<&ProfileSnapshot> {
        self.snapshots.get(app_id)
    }

    pub fn app_count(&self) -> usize {
        self.apps.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installer_type_detection() {
        assert_eq!(InstallerType::detect("setup.exe"), InstallerType::Exe);
        assert_eq!(InstallerType::detect("app.msi"), InstallerType::Msi);
        assert_eq!(InstallerType::detect("readme.txt"), InstallerType::Unknown);
    }

    #[test]
    fn app_install_and_list() {
        let mut db = AppDatabase::new();
        db.install("notepad", "Notepad++", r"C:\Program Files\Notepad++", InstallerType::Exe);
        assert_eq!(db.app_count(), 1);
        assert!(db.get("notepad").is_some());
        assert_eq!(db.get("notepad").unwrap().state, InstallState::Installed);
    }

    #[test]
    fn app_snapshot_and_repair() {
        let mut db = AppDatabase::new();
        db.install("test-app", "Test App", r"C:\Apps\Test", InstallerType::Exe);
        db.snapshot("test-app").unwrap();
        assert!(db.get_snapshot("test-app").is_some());
        db.repair("test-app").unwrap();
        assert_eq!(db.get("test-app").unwrap().state, InstallState::Repaired);
    }

    #[test]
    fn repair_nonexistent_fails() {
        let mut db = AppDatabase::new();
        assert!(db.repair("nonexistent").is_err());
    }

    #[test]
    fn snapshot_nonexistent_fails() {
        let mut db = AppDatabase::new();
        assert!(db.snapshot("nonexistent").is_err());
    }
}
