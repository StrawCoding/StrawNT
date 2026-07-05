use std::path::{Path, PathBuf};

use crate::entry::{AppEntry, AppRegistryFile};

/// Normalize a desktop path for registry lookup (absolute, no trailing slash).
pub fn normalize_desktop_path(raw: &str) -> PathBuf {
    let path = Path::new(raw.trim());
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        PathBuf::from(raw.trim())
    }
}

pub fn desktop_path_key(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

/// Derive a registry app id slug from a `.desktop` basename.
pub fn slug_from_desktop_basename(path: &Path) -> Option<String> {
    let name = path.file_name()?.to_string_lossy();
    let stem = name.strip_suffix(".desktop").unwrap_or(&name);
    if stem.is_empty() {
        return None;
    }
    let slug = stem.to_ascii_lowercase();
    if slug
        .chars()
        .next()
        .map(|c| c.is_ascii_alphanumeric())
        .unwrap_or(false)
        && slug
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
        && slug.len() <= 64
    {
        Some(slug)
    } else {
        None
    }
}

pub fn find_by_desktop<'a>(registry: &'a AppRegistryFile, raw: &str) -> Option<&'a AppEntry> {
    let target = normalize_desktop_path(raw);
    let basename = target.file_name().map(|n| n.to_string_lossy().into_owned());

    registry.apps.iter().find(|app| {
        if let Some(desktop) = &app.desktop_entry {
            let stored = normalize_desktop_path(desktop);
            if stored == target {
                return true;
            }
            if let (Some(a), Some(b)) = (stored.file_name(), target.file_name()) {
                if a == b {
                    return true;
                }
            }
        }
        if let Some(ref base) = basename {
            if app.id == *base || app.id == base.strip_suffix(".desktop").unwrap_or(base) {
                return true;
            }
        }
        false
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entry::{AppKind, AppRegistryFile, AppSource, InstallState};

    fn sample_registry() -> AppRegistryFile {
        AppRegistryFile {
            schema_version: "1.0".into(),
            updated_at: None,
            apps: vec![crate::entry::AppEntry {
                id: "demo-app".into(),
                name: "Demo".into(),
                kind: AppKind::Win32,
                source: AppSource::Launcher,
                install_state: InstallState::Installed,
                protected: false,
                install_path: None,
                desktop_entry: Some("/home/user/.local/share/applications/demo-app.desktop".into()),
                execution_backend: None,
                created_at: None,
                updated_at: None,
            }],
        }
    }

    #[test]
    fn slug_from_basename_valid() {
        assert_eq!(
            slug_from_desktop_basename(Path::new("Demo-App.desktop")).as_deref(),
            Some("demo-app")
        );
    }

    #[test]
    fn find_by_desktop_path() {
        let registry = sample_registry();
        let found = find_by_desktop(
            &registry,
            "/home/user/.local/share/applications/demo-app.desktop",
        );
        assert_eq!(found.map(|a| a.id.as_str()), Some("demo-app"));
    }

    #[test]
    fn find_by_desktop_basename_only() {
        let registry = sample_registry();
        let found = find_by_desktop(&registry, "demo-app.desktop");
        assert_eq!(found.map(|a| a.id.as_str()), Some("demo-app"));
    }
}
