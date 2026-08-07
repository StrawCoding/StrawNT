//! Permissions / capability grants (interop cross-prefix etc.).

use crate::store::{ensure_layout, load_db, permissions_path, save_db, AppMgrError};
use serde_json::{json, Value};
use std::fs;
use std::path::Path;

fn load_grants(home: &Path) -> Result<Value, AppMgrError> {
    let path = permissions_path(home);
    if !path.exists() {
        return Ok(json!({
            "schema": "strawnt-appmgr-permissions/v1",
            "grants": []
        }));
    }
    let text = fs::read_to_string(&path)?;
    Ok(serde_json::from_str(&text)?)
}

fn save_grants(home: &Path, data: &Value) -> Result<(), AppMgrError> {
    let path = permissions_path(home);
    let text = serde_json::to_string_pretty(data)?;
    fs::write(path, format!("{text}\n"))?;
    Ok(())
}

pub fn list_permissions(app_id: Option<&str>, home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let data = load_grants(&root)?;
    let mut grants = data
        .get("grants")
        .and_then(|g| g.as_array())
        .cloned()
        .unwrap_or_default();
    if let Some(id) = app_id {
        grants.retain(|g| g.get("app_id").and_then(|v| v.as_str()) == Some(id));
        let db = load_db(&root)?;
        let app_perms = db
            .find(id)
            .map(|a| a.permissions.clone())
            .unwrap_or_default();
        return Ok(json!({
            "status": "PASS",
            "command": "apps permissions",
            "app_id": id,
            "manifest_permissions": app_perms,
            "grants": grants,
            "execution_backend": "wine",
            "powered_by": "Wine",
            "powered_by_wine": true,
            "notes": [
                "cross-prefix IPC is default-deny; grant via App Manager",
                "not a ranked / vendor anti-cheat PASS",
            ]
        }));
    }
    Ok(json!({
        "status": "PASS",
        "command": "apps permissions",
        "grants": grants,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

pub fn grant_permission(
    app_id: &str,
    capability: &str,
    home: Option<&Path>,
) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let mut db = load_db(&root)?;
    let app = db
        .apps
        .iter_mut()
        .find(|a| a.id == app_id && a.install_state != crate::manifest::InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;
    if !app.permissions.iter().any(|p| p == capability) {
        app.permissions.push(capability.to_string());
    }
    app.touch();
    save_db(&root, &db)?;

    let mut data = load_grants(&root)?;
    let grants = data
        .as_object_mut()
        .ok_or_else(|| AppMgrError::Message("permissions db corrupt".into()))?
        .entry("grants")
        .or_insert_with(|| json!([]));
    let arr = grants
        .as_array_mut()
        .ok_or_else(|| AppMgrError::Message("grants not array".into()))?;
    let exists = arr.iter().any(|g| {
        g.get("app_id").and_then(|v| v.as_str()) == Some(app_id)
            && g.get("capability").and_then(|v| v.as_str()) == Some(capability)
    });
    if !exists {
        arr.push(json!({
            "app_id": app_id,
            "capability": capability,
            "granted_at": strawnt_engine::unix_secs(),
            "default_deny_cross_prefix": capability != "interop.cross_prefix",
        }));
    }
    save_grants(&root, &data)?;

    Ok(json!({
        "status": "PASS",
        "command": "apps permissions grant",
        "app_id": app_id,
        "capability": capability,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

pub fn revoke_permission(
    app_id: &str,
    capability: &str,
    home: Option<&Path>,
) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let mut db = load_db(&root)?;
    if let Some(app) = db
        .apps
        .iter_mut()
        .find(|a| a.id == app_id)
    {
        app.permissions.retain(|p| p != capability);
        app.touch();
        save_db(&root, &db)?;
    }

    let mut data = load_grants(&root)?;
    if let Some(arr) = data.get_mut("grants").and_then(|g| g.as_array_mut()) {
        arr.retain(|g| {
            !(g.get("app_id").and_then(|v| v.as_str()) == Some(app_id)
                && g.get("capability").and_then(|v| v.as_str()) == Some(capability))
        });
    }
    save_grants(&root, &data)?;

    Ok(json!({
        "status": "PASS",
        "command": "apps permissions revoke",
        "app_id": app_id,
        "capability": capability,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}
