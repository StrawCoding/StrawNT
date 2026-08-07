//! App Manager persistence under StrawNT home.

use crate::manifest::AppMgrDb;
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppMgrError {
    #[error("{0}")]
    Message(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
}

pub fn appmgr_dir(home: &Path) -> PathBuf {
    home.join("appmgr")
}

pub fn db_path(home: &Path) -> PathBuf {
    appmgr_dir(home).join("apps.json")
}

pub fn permissions_path(home: &Path) -> PathBuf {
    appmgr_dir(home).join("permissions.json")
}

pub fn ensure_layout(override_home: Option<&Path>) -> Result<PathBuf, AppMgrError> {
    let root = strawnt_engine::paths::ensure_layout(override_home)
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    fs::create_dir_all(appmgr_dir(&root))?;
    let db = db_path(&root);
    if !db.exists() {
        save_db(&root, &AppMgrDb::new())?;
    }
    let perms = permissions_path(&root);
    if !perms.exists() {
        fs::write(&perms, "{\n  \"schema\": \"strawnt-appmgr-permissions/v1\",\n  \"grants\": []\n}\n")?;
    }
    Ok(root)
}

pub fn load_db(home: &Path) -> Result<AppMgrDb, AppMgrError> {
    let path = db_path(home);
    if !path.exists() {
        return Ok(AppMgrDb::new());
    }
    let text = fs::read_to_string(&path)?;
    let mut db: AppMgrDb = serde_json::from_str(&text)?;
    if db.schema.is_empty() {
        db.schema = "strawnt-appmgr-db/v1".into();
    }
    if db.channel.is_empty() {
        db.channel = "stable".into();
    }
    Ok(db)
}

pub fn save_db(home: &Path, db: &AppMgrDb) -> Result<(), AppMgrError> {
    let path = db_path(home);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let text = serde_json::to_string_pretty(db)?;
    fs::write(path, format!("{text}\n"))?;
    Ok(())
}

pub fn catalog_path_in_repo(repo: &Path) -> PathBuf {
    repo.join("components/strawnt-appmgr/catalog/local-catalog.json")
}
