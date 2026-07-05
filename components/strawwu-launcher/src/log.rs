use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

use serde::Serialize;

pub fn wincompat_log_path() -> PathBuf {
    std::env::var("STRAWWU_WINCOMPAT_LOG")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/log/strawwu/wincompat.log"))
}

pub fn append_event<T: Serialize>(event: &str, payload: &T) -> Result<(), String> {
    let path = wincompat_log_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let line = serde_json::json!({
        "event": event,
        "payload": payload,
    });

    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| e.to_string())?;
    writeln!(file, "{line}").map_err(|e| e.to_string())?;
    Ok(())
}
