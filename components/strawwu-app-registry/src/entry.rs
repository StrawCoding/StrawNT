use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum AppKind {
    Win32,
    Linux,
    Flatpak,
    Native,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum AppSource {
    Installer,
    Launcher,
    Flatpak,
    Seed,
    Manual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum InstallState {
    Pending,
    Installing,
    Installed,
    Failed,
    Removed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ExecutionBackend {
    Native,
    Container,
    Microvm,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppEntry {
    pub id: String,
    pub name: String,
    pub kind: AppKind,
    pub source: AppSource,
    pub install_state: InstallState,
    #[serde(default)]
    pub protected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub install_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub desktop_entry: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub execution_backend: Option<ExecutionBackend>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}

impl AppEntry {
    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        kind: AppKind,
        source: AppSource,
    ) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            id: id.into(),
            name: name.into(),
            kind,
            source,
            install_state: InstallState::Installed,
            protected: false,
            install_path: None,
            desktop_entry: None,
            execution_backend: Some(ExecutionBackend::Native),
            created_at: Some(now.clone()),
            updated_at: Some(now),
        }
    }

    pub fn touch(&mut self) {
        self.updated_at = Some(chrono::Utc::now().to_rfc3339());
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppRegistryFile {
    pub schema_version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub apps: Vec<AppEntry>,
}

impl Default for AppRegistryFile {
    fn default() -> Self {
        Self {
            schema_version: crate::validate::SCHEMA_VERSION.to_string(),
            updated_at: Some(chrono::Utc::now().to_rfc3339()),
            apps: Vec::new(),
        }
    }
}

impl AppRegistryFile {
    pub fn touch(&mut self) {
        self.updated_at = Some(chrono::Utc::now().to_rfc3339());
    }

    pub fn find(&self, id: &str) -> Option<&AppEntry> {
        self.apps.iter().find(|app| app.id == id)
    }

    pub fn find_mut(&mut self, id: &str) -> Option<&mut AppEntry> {
        self.apps.iter_mut().find(|app| app.id == id)
    }

    pub fn active_apps(&self) -> Vec<&AppEntry> {
        self.apps
            .iter()
            .filter(|app| app.install_state != InstallState::Removed)
            .collect()
    }
}
