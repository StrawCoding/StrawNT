//! Local store catalog (line.exe / steam.exe P0 seeds).

use crate::store::{catalog_path_in_repo, AppMgrError};
use serde_json::{json, Value};
use std::fs;
use std::path::Path;

pub fn list_catalog() -> Result<Value, AppMgrError> {
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let path = catalog_path_in_repo(&repo);
    if !path.is_file() {
        return Err(AppMgrError::Message(format!(
            "catalog missing: {}",
            path.display()
        )));
    }
    let text = fs::read_to_string(&path)?;
    let mut data: Value = serde_json::from_str(&text)?;
    data["command"] = json!("apps catalog");
    data["status"] = json!("PASS");
    data["catalog_path"] = json!(path.display().to_string());
    data["powered_by_wine"] = json!(true);
    Ok(data)
}

pub fn find_catalog_entry(id: &str) -> Result<Value, AppMgrError> {
    let catalog = list_catalog()?;
    let entries = catalog
        .get("entries")
        .and_then(|e| e.as_array())
        .cloned()
        .unwrap_or_default();
    entries
        .into_iter()
        .find(|e| e.get("id").and_then(|v| v.as_str()) == Some(id))
        .ok_or_else(|| AppMgrError::Message(format!("catalog entry not found: {id}")))
}

/// Resolve engine pin for manifests.
pub fn current_pin(repo: &Path) -> Option<String> {
    strawnt_engine::load_pin(repo).ok().map(|p| p.tag)
}
