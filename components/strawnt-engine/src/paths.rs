//! XDG data paths for StrawNT prefixes, matrix, and recipe state.
//! Pattern absorbed from straw-wine (`paths.py`); product home is `strawnt`.

use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use crate::{EngineError, Result};

pub fn data_home() -> PathBuf {
    if let Ok(xdg) = env::var("XDG_DATA_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg);
        }
    }
    dirs_home().join(".local/share")
}

fn dirs_home() -> PathBuf {
    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

/// Resolve StrawNT data home. Override via `STRAWNT_HOME` or explicit path.
pub fn strawnt_home(override_home: Option<&Path>) -> PathBuf {
    if let Some(p) = override_home {
        return p.to_path_buf();
    }
    if let Ok(env_home) = env::var("STRAWNT_HOME") {
        if !env_home.is_empty() {
            return PathBuf::from(env_home);
        }
    }
    data_home().join("strawnt")
}

pub fn prefixes_dir(home: &Path) -> PathBuf {
    home.join("prefixes")
}

pub fn index_path(home: &Path) -> PathBuf {
    home.join("prefixes.json")
}

pub fn matrix_path(home: &Path) -> PathBuf {
    home.join("matrix.json")
}

pub fn ensure_layout(override_home: Option<&Path>) -> Result<PathBuf> {
    let root = strawnt_home(override_home);
    fs::create_dir_all(prefixes_dir(&root))?;
    let idx = index_path(&root);
    if !idx.exists() {
        write_json(&idx, &json!({"version": 1, "prefixes": {}}))?;
    }
    let mx = matrix_path(&root);
    if !mx.exists() {
        write_json(&mx, &json!({"version": 1, "entries": {}}))?;
    }
    Ok(root)
}

pub fn read_json(path: &Path) -> Result<Value> {
    if !path.exists() {
        return Ok(json!({}));
    }
    let text = fs::read_to_string(path)?;
    serde_json::from_str(&text).map_err(|e| EngineError::Message(format!("json {}: {e}", path.display())))
}

pub fn write_json(path: &Path, value: &Value) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let text = serde_json::to_string_pretty(value)
        .map_err(|e| EngineError::Message(format!("serialize: {e}")))?;
    fs::write(path, format!("{text}\n"))?;
    Ok(())
}

pub fn read_index(home: &Path) -> Result<Value> {
    let path = index_path(home);
    let mut data = if path.exists() {
        read_json(&path)?
    } else {
        json!({"version": 1, "prefixes": {}})
    };
    if !data.is_object() {
        data = json!({"version": 1, "prefixes": {}});
    }
    if data.get("version").is_none() {
        data["version"] = json!(1);
    }
    if data.get("prefixes").is_none() {
        data["prefixes"] = json!({});
    }
    Ok(data)
}

pub fn write_index(home: &Path, data: &Value) -> Result<()> {
    write_json(&index_path(home), data)
}

pub fn read_matrix(home: &Path) -> Result<Value> {
    let path = matrix_path(home);
    let mut data = if path.exists() {
        read_json(&path)?
    } else {
        json!({"version": 1, "entries": {}})
    };
    if !data.is_object() {
        data = json!({"version": 1, "entries": {}});
    }
    if data.get("version").is_none() {
        data["version"] = json!(1);
    }
    if data.get("entries").is_none() {
        data["entries"] = json!({});
    }
    Ok(data)
}

pub fn write_matrix(home: &Path, data: &Value) -> Result<()> {
    write_json(&matrix_path(home), data)
}
