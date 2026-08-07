//! App manifest types (schema: strawnt-app-manifest/v1).

use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InstallState {
    Pending,
    Installing,
    Installed,
    Failed,
    Removed,
    Registered,
}

impl InstallState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Installing => "installing",
            Self::Installed => "installed",
            Self::Failed => "failed",
            Self::Removed => "removed",
            Self::Registered => "registered",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppManifest {
    pub schema: String,
    pub id: String,
    pub name: String,
    pub kind: String,
    pub source: String,
    pub install_state: InstallState,
    pub execution_backend: String,
    #[serde(default = "default_engine")]
    pub engine: String,
    #[serde(default)]
    pub engine_pin: Option<String>,
    #[serde(default = "default_powered_by")]
    pub powered_by: String,
    #[serde(default = "default_true")]
    pub powered_by_wine: bool,
    #[serde(default)]
    pub prefix: Option<String>,
    #[serde(default)]
    pub exe: Option<String>,
    #[serde(default)]
    pub install_path: Option<String>,
    #[serde(default)]
    pub recipes_recommended: Vec<String>,
    #[serde(default)]
    pub recipes_applied: Vec<String>,
    #[serde(default = "default_channel")]
    pub update_channel: String,
    #[serde(default)]
    pub permissions: Vec<String>,
    #[serde(default = "default_compat")]
    pub compat_status: String,
    #[serde(default)]
    pub scopes: BTreeMap<String, String>,
    #[serde(default)]
    pub protected: bool,
    #[serde(default)]
    pub system_app: bool,
    #[serde(default)]
    pub dedicated_role: Option<String>,
    #[serde(default)]
    pub honesty: Map<String, Value>,
    #[serde(default)]
    pub created_at: Option<String>,
    #[serde(default)]
    pub updated_at: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

fn default_engine() -> String {
    "proton-ge".into()
}
fn default_powered_by() -> String {
    "Wine".into()
}
fn default_true() -> bool {
    true
}
fn default_channel() -> String {
    "stable".into()
}
fn default_compat() -> String {
    "UNKNOWN".into()
}

impl AppManifest {
    pub fn new(id: impl Into<String>, name: impl Into<String>, kind: impl Into<String>) -> Self {
        let now = now_rfc3339();
        let mut honesty = Map::new();
        honesty.insert("full_windows_claimed".into(), json!(false));
        honesty.insert("ranked_anticheat_claimed".into(), json!(false));
        honesty.insert("simulated".into(), json!(false));
        Self {
            schema: "strawnt-app-manifest/v1".into(),
            id: id.into(),
            name: name.into(),
            kind: kind.into(),
            source: "manual".into(),
            install_state: InstallState::Installed,
            execution_backend: "wine".into(),
            engine: default_engine(),
            engine_pin: None,
            powered_by: default_powered_by(),
            powered_by_wine: true,
            prefix: None,
            exe: None,
            install_path: None,
            recipes_recommended: Vec::new(),
            recipes_applied: Vec::new(),
            update_channel: default_channel(),
            permissions: Vec::new(),
            compat_status: default_compat(),
            scopes: BTreeMap::new(),
            protected: false,
            system_app: false,
            dedicated_role: None,
            honesty,
            created_at: Some(now.clone()),
            updated_at: Some(now),
            notes: None,
        }
    }

    pub fn touch(&mut self) {
        self.updated_at = Some(now_rfc3339());
    }

    pub fn to_value(&self) -> Value {
        serde_json::to_value(self).unwrap_or(json!({}))
    }
}

fn now_rfc3339() -> String {
    // Avoid chrono dep; use unix secs ISO-ish stamp.
    let secs = strawnt_engine::unix_secs();
    format!("{secs}")
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppMgrDb {
    pub schema: String,
    pub version: u32,
    pub updated_at: Option<String>,
    pub apps: Vec<AppManifest>,
    #[serde(default)]
    pub channel: String,
}

impl AppMgrDb {
    pub fn new() -> Self {
        Self {
            schema: "strawnt-appmgr-db/v1".into(),
            version: 1,
            updated_at: Some(now_rfc3339()),
            apps: Vec::new(),
            channel: "stable".into(),
        }
    }

    pub fn touch(&mut self) {
        self.updated_at = Some(now_rfc3339());
    }

    pub fn find(&self, id: &str) -> Option<&AppManifest> {
        self.apps.iter().find(|a| a.id == id)
    }

    pub fn find_mut(&mut self, id: &str) -> Option<&mut AppManifest> {
        self.apps.iter_mut().find(|a| a.id == id)
    }

    pub fn upsert(&mut self, manifest: AppManifest) {
        if let Some(existing) = self.find_mut(&manifest.id) {
            *existing = manifest;
        } else {
            self.apps.push(manifest);
        }
        self.touch();
    }
}
