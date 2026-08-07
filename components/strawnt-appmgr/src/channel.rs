//! Update channel (stable / beta / nightly).

use crate::store::{ensure_layout, load_db, save_db, AppMgrError};
use serde_json::{json, Value};
use std::path::Path;

fn normalize(channel: &str) -> Result<String, AppMgrError> {
    match channel.trim().to_ascii_lowercase().as_str() {
        "stable" => Ok("stable".into()),
        "beta" => Ok("beta".into()),
        "nightly" => Ok("nightly".into()),
        other => Err(AppMgrError::Message(format!(
            "invalid channel '{other}' (use stable|beta|nightly)"
        ))),
    }
}

pub fn get_channel(home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let db = load_db(&root)?;
    Ok(json!({
        "status": "PASS",
        "command": "apps channel",
        "channel": db.channel,
        "allowed": ["stable", "beta", "nightly"],
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "home": root.display().to_string(),
    }))
}

pub fn set_channel(channel: &str, home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let ch = normalize(channel)?;
    let mut db = load_db(&root)?;
    db.channel = ch.clone();
    db.touch();
    save_db(&root, &db)?;
    Ok(json!({
        "status": "PASS",
        "command": "apps channel set",
        "channel": ch,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "home": root.display().to_string(),
    }))
}
