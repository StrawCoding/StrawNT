//! StrawNT system App Manager (NTW5).
//!
//! Owns install/uninstall, list/launch, prefix, deps recipes, update channel,
//! permissions, telemetry/compat, dedicated system apps registry, and local
//! store catalog. Honesty: execution_backend=wine · powered by Wine · never
//! claim full Windows / ranked anti-cheat.

pub mod catalog;
pub mod channel;
pub mod lifecycle;
pub mod manifest;
pub mod permissions;
pub mod smoke;
pub mod store;
pub mod sysapps;

use serde_json::{json, Value};
use std::path::Path;

pub use catalog::list_catalog;
pub use channel::{get_channel, set_channel};
pub use lifecycle::{
    install_catalog, install_path, launch_app, list_apps, show_app, uninstall_app,
};
pub use permissions::{grant_permission, list_permissions, revoke_permission};
pub use smoke::run_appmgr_smoke;
pub use store::AppMgrError;
pub use sysapps::{ensure_sysapps_registered, list_sysapps};

pub type Result<T> = std::result::Result<T, AppMgrError>;

/// Prefix bind / query for an installed app.
pub fn app_prefix(
    app_id: &str,
    set_to: Option<&str>,
    home: Option<&Path>,
) -> Result<Value> {
    let root = store::ensure_layout(home)?;
    let mut db = store::load_db(&root)?;
    let app = db
        .apps
        .iter_mut()
        .find(|a| a.id == app_id && a.install_state != manifest::InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;

    if let Some(name) = set_to {
        let validated = strawnt_engine::prefix::validate_name(name)
            .map_err(|e| AppMgrError::Message(e.to_string()))?;
        // Ensure prefix exists (create if missing).
        let repo = strawnt_engine::find_repo_root()
            .map_err(|e| AppMgrError::Message(e.to_string()))?;
        let created = strawnt_engine::prefix::create_prefix(
            &repo,
            &validated,
            "win64",
            false,
            Some(root.as_path()),
        )
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
        app.prefix = Some(validated.clone());
        app.touch();
        store::save_db(&root, &db)?;
        return Ok(json!({
            "status": "PASS",
            "command": "apps prefix",
            "app_id": app_id,
            "prefix": validated,
            "prefix_create": created,
            "execution_backend": "wine",
            "powered_by": "Wine",
            "powered_by_wine": true,
        }));
    }

    Ok(json!({
        "status": "PASS",
        "command": "apps prefix",
        "app_id": app_id,
        "prefix": app.prefix,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

/// Plan or apply dependency recipes for an app.
pub fn app_recipes(
    app_id: &str,
    apply_id: Option<&str>,
    home: Option<&Path>,
) -> Result<Value> {
    let root = store::ensure_layout(home)?;
    let mut db = store::load_db(&root)?;
    let app = db
        .apps
        .iter_mut()
        .find(|a| a.id == app_id && a.install_state != manifest::InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;

    let recommended = app.recipes_recommended.clone();
    let prefix = app
        .prefix
        .clone()
        .unwrap_or_else(|| app.id.clone());

    if let Some(rid) = apply_id {
        let repo = strawnt_engine::find_repo_root()
            .map_err(|e| AppMgrError::Message(e.to_string()))?;
        let applied = strawnt_engine::recipes::apply_recipe(
            &repo,
            rid,
            &prefix,
            Some(root.as_path()),
        )
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
        if !app.recipes_applied.iter().any(|x| x == rid) {
            app.recipes_applied.push(rid.to_string());
        }
        app.touch();
        store::save_db(&root, &db)?;
        return Ok(json!({
            "status": applied.get("status").cloned().unwrap_or(json!("PARTIAL")),
            "command": "apps recipes",
            "app_id": app_id,
            "prefix": prefix,
            "recommended": recommended,
            "applied_recipe": rid,
            "recipe_result": applied,
            "execution_backend": "wine",
            "powered_by": "Wine",
            "powered_by_wine": true,
        }));
    }

    let plan = strawnt_engine::recipes::list_recipes();
    Ok(json!({
        "status": "PASS",
        "command": "apps recipes",
        "app_id": app_id,
        "prefix": prefix,
        "recommended": recommended,
        "applied": app.recipes_applied,
        "catalog": plan.get("recipes").cloned().unwrap_or(json!([])),
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

/// Compat / telemetry snapshot for an app (matrix row + honesty flags).
pub fn app_compat(app_id: &str, home: Option<&Path>) -> Result<Value> {
    let root = store::ensure_layout(home)?;
    let db = store::load_db(&root)?;
    let app = db
        .apps
        .iter()
        .find(|a| a.id == app_id && a.install_state != manifest::InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;

    let matrix_key = app.exe.clone().unwrap_or_else(|| format!("{}.exe", app.id));
    let matrix = strawnt_engine::matrix::get_entry(&matrix_key, Some(root.as_path()))
        .unwrap_or_else(|_| json!({"found": false, "status": "UNKNOWN"}));

    Ok(json!({
        "status": "PASS",
        "command": "apps compat",
        "app_id": app_id,
        "compat_status": app.compat_status,
        "scopes": app.scopes,
        "matrix": matrix,
        "honesty": {
            "full_windows_claimed": false,
            "ranked_anticheat_claimed": false,
            "simulated": false,
            "powered_by_wine": true,
        },
        "telemetry": {
            "enabled": false,
            "note": "Local compat matrix only — no remote telemetry in NTW5"
        },
        "execution_backend": "wine",
        "engine": app.engine,
        "engine_pin": app.engine_pin,
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

/// High-level status of the App Manager control plane.
pub fn status(home: Option<&Path>) -> Result<Value> {
    let root = store::ensure_layout(home)?;
    ensure_sysapps_registered(Some(root.as_path()))?;
    let db = store::load_db(&root)?;
    let active: Vec<_> = db
        .apps
        .iter()
        .filter(|a| a.install_state != manifest::InstallState::Removed)
        .collect();
    let sys = active.iter().filter(|a| a.system_app).count();
    let ch = get_channel(Some(root.as_path()))?;
    Ok(json!({
        "status": "PASS",
        "command": "apps status",
        "product": "StrawNT",
        "role": "system_manager_app",
        "execution_backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "home": root.display().to_string(),
        "app_count": active.len(),
        "system_app_count": sys,
        "update_channel": ch.get("channel").cloned().unwrap_or(json!("stable")),
        "capabilities": {
            "install": true,
            "uninstall": true,
            "list_launch": true,
            "prefix": true,
            "deps_recipes": true,
            "update_channel": true,
            "permissions": true,
            "telemetry_compat": true,
            "store_catalog": true,
            "dedicated_system_apps": true,
        },
        "notes": [
            "App Manager is the system lifecycle owner (NTW5)",
            "Dedicated UI apps smoke in NTW6",
            "powered by Wine — not a full Windows claim",
        ]
    }))
}
