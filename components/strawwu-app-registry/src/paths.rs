use std::env;
use std::path::{Path, PathBuf};

pub const DEFAULT_REGISTRY_PATH: &str = "/var/lib/strawwu/app-registry.json";
pub const DEFAULT_LOG_PATH: &str = "/var/log/strawwu/app-registry.log";

pub fn default_registry_path() -> PathBuf {
    env::var("STRAWWU_APP_REGISTRY")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_REGISTRY_PATH))
}

pub fn default_log_path() -> PathBuf {
    env::var("STRAWWU_APP_REGISTRY_LOG")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_LOG_PATH))
}

pub fn ensure_parent_dir(path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}
