use std::env;
use std::path::{Path, PathBuf};

pub const DEFAULT_REGISTRY_PATH: &str = "/var/lib/strawnt/app-registry.json";
pub const DEFAULT_LOG_PATH: &str = "/var/log/strawnt/app-registry.log";

fn env_first(keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Ok(v) = env::var(key) {
            if !v.is_empty() {
                return Some(v);
            }
        }
    }
    None
}

pub fn default_registry_path() -> PathBuf {
    env_first(&["STRAWNT_APP_REGISTRY", "STRAWWU_APP_REGISTRY"])
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_REGISTRY_PATH))
}

pub fn default_log_path() -> PathBuf {
    env_first(&["STRAWNT_APP_REGISTRY_LOG", "STRAWWU_APP_REGISTRY_LOG"])
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_LOG_PATH))
}

pub fn ensure_parent_dir(path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}
