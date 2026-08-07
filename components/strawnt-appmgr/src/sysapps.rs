//! Dedicated system apps registry (NTW5 register; NTW6 thin UI slices).

use crate::manifest::{AppManifest, InstallState};
use crate::store::{ensure_layout, load_db, save_db, AppMgrError};
use serde_json::{json, Value};
use std::path::Path;

/// Locked dedicated system apps from Wine pivot plan.
pub const DEDICATED_SYSAPPS: &[(&str, &str, &str)] = &[
    ("sys-app-manager", "App Manager", "app_manager"),
    ("sys-file-manager", "File Manager", "file_manager"),
    ("sys-settings", "Settings", "settings"),
    ("sys-run-dialog", "Run Dialog", "run_dialog"),
    ("sys-task-manager", "Task Manager", "task_manager"),
    ("sys-app-library", "App Library", "app_library"),
    ("sys-installer-wizard", "Installer Wizard", "installer_wizard"),
    ("sys-compat-center", "Compat Center", "compat_center"),
];

pub fn ensure_sysapps_registered(home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let pin = strawnt_engine::load_pin(&repo)
        .ok()
        .map(|p| p.tag);
    let mut db = load_db(&root)?;
    let mut registered = Vec::new();

    for (id, name, role) in DEDICATED_SYSAPPS {
        let exists = db
            .apps
            .iter()
            .any(|a| a.id == *id && a.install_state != InstallState::Removed);
        if exists {
            registered.push(json!({"id": id, "role": role, "action": "exists"}));
            continue;
        }
        let mut m = AppManifest::new(*id, *name, "system");
        m.source = "system".into();
        m.install_state = InstallState::Registered;
        m.protected = true;
        m.system_app = true;
        m.dedicated_role = Some((*role).into());
        m.compat_status = "PARTIAL".into();
        m.engine_pin = pin.clone();
        m.notes = Some(format!(
            "Dedicated system app '{role}' — NTW6 thin UI slice; App Manager owns lifecycle"
        ));
        m.scopes.insert("registered".into(), "PASS".into());
        m.scopes.insert("ui".into(), "PARTIAL".into());
        m.scopes.insert("launch".into(), "PASS".into());
        db.upsert(m);
        registered.push(json!({"id": id, "role": role, "action": "registered"}));
    }
    save_db(&root, &db)?;

    Ok(json!({
        "status": "PASS",
        "command": "apps sysapps ensure",
        "count": DEDICATED_SYSAPPS.len(),
        "registered": registered,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "notes": [
            "NTW5 registers dedicated apps; NTW6 delivers thin UI vertical slices",
            "app_manager is the system manager surface",
        ]
    }))
}

pub fn list_sysapps(home: Option<&Path>) -> Result<Value, AppMgrError> {
    ensure_sysapps_registered(home)?;
    let root = ensure_layout(home)?;
    let db = load_db(&root)?;
    let apps: Vec<Value> = db
        .apps
        .iter()
        .filter(|a| a.system_app && a.install_state != InstallState::Removed)
        .map(|a| a.to_value())
        .collect();
    let roles: Vec<&str> = DEDICATED_SYSAPPS.iter().map(|(_, _, r)| *r).collect();
    Ok(json!({
        "status": "PASS",
        "command": "apps sysapps",
        "count": apps.len(),
        "roles": roles,
        "apps": apps,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "home": root.display().to_string(),
    }))
}
