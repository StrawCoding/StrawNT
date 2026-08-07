//! StrawNT dedicated system apps (NTW6).
//!
//! Thin vertical slices: settings, run_dialog, installer_wizard, app_library,
//! compat_center, task_manager, file_manager. Each has manifest + launch entry
//! + smoke. Honesty: execution_backend=wine · powered by Wine · never claim
//! full Windows / ranked anti-cheat. Hub = Electron.

pub mod launch;
pub mod roles;
pub mod smoke;

pub use launch::{launch_role, launch_sysapp_id, side_effect_dir};
pub use roles::{
    DedicatedRole, DEDICATED_ROLES, ROLE_TO_APP_ID, SYSAPP_COUNT,
};
pub use smoke::run_sysapps_smoke;

use serde_json::{json, Value};
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SysAppsError {
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    AppMgr(#[from] strawnt_appmgr::AppMgrError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, SysAppsError>;

/// List dedicated system apps with manifest paths + desktop launch entries.
pub fn list_apps(home: Option<&Path>) -> Result<Value> {
    let _ = strawnt_appmgr::ensure_sysapps_registered(home)?;
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| SysAppsError::Message(e.to_string()))?;
    let pin = strawnt_engine::load_pin(&repo)
        .map(|p| p.tag)
        .unwrap_or_else(|_| "unknown".into());

    let mut apps = Vec::new();
    for role in DEDICATED_ROLES {
        let id = role.app_id();
        let manifest_rel = format!("components/strawnt-sysapps/manifests/{}.json", role.as_str());
        let desktop_rel = format!(
            "hub/resources/desktop/strawnt-{}.desktop",
            role.as_str().replace('_', "-")
        );
        let manifest_path = repo.join(&manifest_rel);
        let desktop_path = repo.join(&desktop_rel);
        let hub_tab = role.hub_tab();
        apps.push(json!({
            "id": id,
            "role": role.as_str(),
            "name": role.display_name(),
            "kind": "system",
            "system_app": true,
            "dedicated_role": role.as_str(),
            "manifest": manifest_rel,
            "manifest_present": manifest_path.is_file(),
            "desktop": desktop_rel,
            "desktop_present": desktop_path.is_file(),
            "hub": "electron",
            "hub_tab": hub_tab,
            "launch_entry": format!("strawnt sysapps launch {}", role.as_str()),
            "execution_backend": "wine",
            "engine": "proton-ge",
            "engine_pin": pin,
            "powered_by": "Wine",
            "powered_by_wine": true,
        }));
    }

    Ok(json!({
        "status": "PASS",
        "command": "sysapps list",
        "schema": "strawnt-sysapps-list/v1",
        "product": "StrawNT",
        "count": apps.len(),
        "apps": apps,
        "hub": "electron",
        "execution_backend": "wine",
        "engine": "proton-ge",
        "engine_pin": pin,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "notes": [
            "NTW6 dedicated system apps — thin vertical slices",
            "powered by Wine — not a full Windows / ranked anti-cheat claim",
        ]
    }))
}

/// Load a single app manifest JSON from the repo tree.
pub fn load_manifest(role: DedicatedRole) -> Result<Value> {
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| SysAppsError::Message(e.to_string()))?;
    let path = repo
        .join("components/strawnt-sysapps/manifests")
        .join(format!("{}.json", role.as_str()));
    if !path.is_file() {
        return Err(SysAppsError::Message(format!(
            "manifest missing: {}",
            path.display()
        )));
    }
    let text = std::fs::read_to_string(&path)?;
    let mut v: Value = serde_json::from_str(&text)?;
    if let Some(obj) = v.as_object_mut() {
        obj.insert("manifest_path".into(), json!(path.display().to_string()));
    }
    Ok(v)
}
