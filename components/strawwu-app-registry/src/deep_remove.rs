use std::fs;
use std::path::{Component, Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use thiserror::Error;

use crate::entry::{AppEntry, AppKind, AppSource, InstallState};
use crate::registry::RemovePreview;

#[derive(Debug, Error)]
pub enum DeepRemoveError {
    #[error("path not deletable (system or outside allowlist): {0}")]
    ForbiddenPath(String),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("flatpak uninstall failed: {0}")]
    Flatpak(String),
}

#[derive(Debug, Clone, Serialize)]
pub struct SkippedPath {
    pub path: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct FlatpakUninstallResult {
    pub app_id: String,
    pub executed: bool,
    pub skipped_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeepRemovePlan {
    pub id: String,
    pub paths_to_delete: Vec<PathBuf>,
    pub paths_skipped: Vec<SkippedPath>,
    pub flatpak_app_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeepRemoveResult {
    pub preview: RemovePreview,
    pub dry_run: bool,
    pub registry_removed: bool,
    pub paths_deleted: Vec<String>,
    pub paths_skipped: Vec<SkippedPath>,
    pub flatpak: Option<FlatpakUninstallResult>,
}

const FORBIDDEN_PREFIXES: &[&str] = &[
    "/usr",
    "/etc",
    "/bin",
    "/sbin",
    "/lib",
    "/lib32",
    "/lib64",
    "/libx32",
    "/boot",
    "/sys",
    "/proc",
    "/dev",
    "/run",
    "/root",
    "/var/lib/dpkg",
    "/var/lib/apt",
    "/var/lib/strawwu",
];

pub fn default_allow_prefixes() -> Vec<PathBuf> {
    let mut prefixes = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        let home = PathBuf::from(home);
        prefixes.push(home.join(".strawwu"));
        prefixes.push(home.join(".local/share/applications"));
        prefixes.push(home.join(".var/app"));
        prefixes.push(home.join(".local/share/flatpak"));
        prefixes.push(home.join(".wine"));
    }
    prefixes.push(PathBuf::from("/opt/strawwu/apps"));
    if let Ok(extra) = std::env::var("STRAWWU_DEEP_REMOVE_ALLOW_PREFIXES") {
        for part in extra.split(':').filter(|p| !p.is_empty()) {
            prefixes.push(PathBuf::from(part));
        }
    }
    prefixes
}

pub fn is_forbidden_system_path(path: &Path) -> bool {
    let normalized = normalize_path(path);
    FORBIDDEN_PREFIXES
        .iter()
        .any(|prefix| path_has_prefix(&normalized, Path::new(prefix)))
}

pub fn is_deletable_path(path: &Path, allow_prefixes: &[PathBuf]) -> bool {
    if !path.is_absolute() {
        return false;
    }
    if path
        .components()
        .any(|c| matches!(c, Component::ParentDir))
    {
        return false;
    }
    if is_forbidden_system_path(path) {
        return false;
    }
    let normalized = normalize_path(path);
    allow_prefixes
        .iter()
        .any(|prefix| path_has_prefix(&normalized, prefix))
}

pub fn plan_deep_remove(app: &AppEntry) -> DeepRemovePlan {
    let allow = default_allow_prefixes();
    let mut paths_to_delete = Vec::new();
    let mut paths_skipped = Vec::new();

    for raw in [app.install_path.as_deref(), app.desktop_entry.as_deref()]
        .into_iter()
        .flatten()
    {
        let path = PathBuf::from(raw);
        if path.as_os_str().is_empty() {
            continue;
        }
        if app.kind == AppKind::Flatpak && !path.is_absolute() {
            continue;
        }
        if is_deletable_path(&path, &allow) {
            if !paths_to_delete.iter().any(|p| p == &path) {
                paths_to_delete.push(path);
            }
        } else {
            paths_skipped.push(SkippedPath {
                path: raw.to_string(),
                reason: if is_forbidden_system_path(&path) {
                    "system path blocked".into()
                } else {
                    "outside deep-remove allowlist".into()
                },
            });
        }
    }

    let flatpak_app_id = if app.kind == AppKind::Flatpak {
        app.install_path.clone()
    } else {
        None
    };

    DeepRemovePlan {
        id: app.id.clone(),
        paths_to_delete,
        paths_skipped,
        flatpak_app_id,
    }
}

pub fn execute_deep_remove_plan(
    plan: &DeepRemovePlan,
    dry_run: bool,
) -> Result<(Vec<String>, Option<FlatpakUninstallResult>), DeepRemoveError> {
    let mut deleted = Vec::new();

    for path in &plan.paths_to_delete {
        if dry_run {
            deleted.push(path.to_string_lossy().into_owned());
            continue;
        }
        if path.is_dir() {
            fs::remove_dir_all(path)?;
        } else if path.exists() {
            fs::remove_file(path)?;
        }
        deleted.push(path.to_string_lossy().into_owned());
    }

    let flatpak = if let Some(ref app_id) = plan.flatpak_app_id {
        Some(run_flatpak_uninstall(app_id, dry_run)?)
    } else {
        None
    };

    Ok((deleted, flatpak))
}

fn run_flatpak_uninstall(app_id: &str, dry_run: bool) -> Result<FlatpakUninstallResult, DeepRemoveError> {
    if dry_run {
        return Ok(FlatpakUninstallResult {
            app_id: app_id.to_string(),
            executed: false,
            skipped_reason: None,
        });
    }

    if std::env::var("STRAWWU_SKIP_FLATPAK_UNINSTALL").is_ok() {
        return Ok(FlatpakUninstallResult {
            app_id: app_id.to_string(),
            executed: false,
            skipped_reason: Some("STRAWWU_SKIP_FLATPAK_UNINSTALL set".into()),
        });
    }

    let output = Command::new("flatpak")
        .args(["uninstall", "-y", "--system", app_id])
        .output()
        .map_err(|e| DeepRemoveError::Flatpak(e.to_string()))?;

    if output.status.success() {
        Ok(FlatpakUninstallResult {
            app_id: app_id.to_string(),
            executed: true,
            skipped_reason: None,
        })
    } else {
        let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
        Err(DeepRemoveError::Flatpak(if detail.is_empty() {
            format!("flatpak uninstall failed for {app_id}")
        } else {
            detail
        }))
    }
}

pub fn should_sync_remove_on_scan(app: &AppEntry) -> bool {
    if app.protected || app.install_state != InstallState::Installed {
        return false;
    }
    if app.source == AppSource::Launcher {
        return false;
    }
    if app.source == AppSource::Installer && app.kind == AppKind::Win32 {
        return false;
    }
    if app.source == AppSource::Seed {
        return false;
    }
    matches!(
        (app.kind, app.source),
        (AppKind::Linux, AppSource::Manual)
            | (AppKind::Flatpak, AppSource::Flatpak)
    )
}

fn normalize_path(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(p) => out.push(p.as_os_str()),
            Component::RootDir => out.push("/"),
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            Component::Normal(part) => out.push(part),
        }
    }
    out
}

fn path_has_prefix(path: &Path, prefix: &Path) -> bool {
    path == prefix || path.strip_prefix(prefix).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::AppKind;
    use tempfile::tempdir;

    #[test]
    fn blocks_system_paths() {
        assert!(is_forbidden_system_path(Path::new("/usr/bin/foo")));
        assert!(is_forbidden_system_path(Path::new("/etc/passwd")));
        assert!(!is_forbidden_system_path(Path::new("/opt/strawwu/apps/demo")));
    }

    #[test]
    fn allowlist_permits_strawwu_prefix() {
        let dir = tempdir().unwrap();
        let prefix = dir.path().join("apps");
        let target = prefix.join("demo-app");
        let allow = vec![dir.path().to_path_buf()];
        assert!(is_deletable_path(&target, &allow));
    }

    #[test]
    fn plan_skips_flatpak_ref_as_path() {
        let app = AppEntry::new("org.gnome.calculator", "Calc", AppKind::Flatpak, AppSource::Flatpak);
        let mut app = app;
        app.install_path = Some("org.gnome.Calculator".into());
        let plan = plan_deep_remove(&app);
        assert!(plan.paths_to_delete.is_empty());
        assert_eq!(plan.flatpak_app_id.as_deref(), Some("org.gnome.Calculator"));
    }

    #[test]
    fn execute_dry_run_does_not_touch_disk() {
        let dir = tempdir().unwrap();
        let app_dir = dir.path().join("demo");
        fs::create_dir_all(&app_dir).unwrap();
        let plan = DeepRemovePlan {
            id: "demo".into(),
            paths_to_delete: vec![app_dir.clone()],
            paths_skipped: vec![],
            flatpak_app_id: None,
        };
        let (deleted, _) = execute_deep_remove_plan(&plan, true).unwrap();
        assert_eq!(deleted.len(), 1);
        assert!(app_dir.exists());
    }

    #[test]
    fn execute_removes_allowlisted_tree() {
        let dir = tempdir().unwrap();
        let app_dir = dir.path().join("demo");
        fs::create_dir_all(app_dir.join("data")).unwrap();
        let plan = DeepRemovePlan {
            id: "demo".into(),
            paths_to_delete: vec![app_dir.clone()],
            paths_skipped: vec![],
            flatpak_app_id: None,
        };
        execute_deep_remove_plan(&plan, false).unwrap();
        assert!(!app_dir.exists());
    }
}
