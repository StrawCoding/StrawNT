use std::path::{Path, PathBuf};
use std::process::Command;

use crate::desktop::slug_from_desktop_basename;
use crate::entry::{AppKind, AppSource};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScannedApp {
    pub id: String,
    pub name: String,
    pub kind: AppKind,
    pub source: AppSource,
    pub install_path: Option<String>,
    pub desktop_entry: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct ScanOptions {
    pub linux: bool,
    pub flatpak: bool,
    pub linux_dirs: Vec<PathBuf>,
    pub flatpak_list_file: Option<PathBuf>,
}

impl ScanOptions {
    pub fn all() -> Self {
        Self {
            linux: true,
            flatpak: true,
            linux_dirs: default_linux_desktop_dirs(),
            flatpak_list_file: std::env::var("STRAWWU_FLATPAK_LIST_FILE")
                .ok()
                .map(PathBuf::from),
        }
    }

    pub fn with_linux(mut self) -> Self {
        self.linux = true;
        self
    }

    pub fn with_flatpak(mut self) -> Self {
        self.flatpak = true;
        self
    }
}

pub fn default_linux_desktop_dirs() -> Vec<PathBuf> {
    if let Ok(raw) = std::env::var("STRAWWU_LINUX_DESKTOP_DIRS") {
        return raw
            .split(':')
            .filter(|part| !part.is_empty())
            .map(PathBuf::from)
            .collect();
    }
    vec![
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
    ]
}

pub fn scan_apps(options: &ScanOptions) -> Vec<ScannedApp> {
    let mut apps = Vec::new();
    if options.linux {
        for dir in &options.linux_dirs {
            apps.extend(scan_linux_desktop_dir(dir));
        }
    }
    if options.flatpak {
        apps.extend(scan_flatpak_apps(options.flatpak_list_file.as_deref()));
    }
    apps.sort_by(|a, b| a.id.cmp(&b.id));
    apps.dedup_by(|a, b| a.id == b.id);
    apps
}

pub fn scan_linux_desktop_dir(dir: &Path) -> Vec<ScannedApp> {
    let mut apps = Vec::new();
    let entries = match std::fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return apps,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
            continue;
        }
        if let Some(app) = scan_linux_desktop_file(&path) {
            apps.push(app);
        }
    }
    apps
}

pub fn scan_linux_desktop_file(path: &Path) -> Option<ScannedApp> {
    let id = slug_from_desktop_basename(path)?;
    let meta = parse_desktop_metadata(path)?;
    if meta.hidden || meta.no_display {
        return None;
    }
    if meta.entry_type.as_deref() != Some("Application") {
        return None;
    }
    if meta.exec.as_deref().unwrap_or("").trim().is_empty() {
        return None;
    }
    let name = meta.name?.trim().to_string();
    if name.is_empty() {
        return None;
    }

    Some(ScannedApp {
        id,
        name,
        kind: AppKind::Linux,
        source: AppSource::Manual,
        install_path: meta.exec,
        desktop_entry: Some(path.to_string_lossy().into_owned()),
    })
}

#[derive(Debug, Default)]
struct DesktopMetadata {
    name: Option<String>,
    exec: Option<String>,
    entry_type: Option<String>,
    hidden: bool,
    no_display: bool,
}

fn parse_desktop_metadata(path: &Path) -> Option<DesktopMetadata> {
    let raw = std::fs::read_to_string(path).ok()?;
    let mut meta = DesktopMetadata::default();
    let mut in_entry = false;

    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_entry = line.eq_ignore_ascii_case("[Desktop Entry]");
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        match key {
            "Name" if meta.name.is_none() => meta.name = Some(value.to_string()),
            "Exec" if meta.exec.is_none() => meta.exec = Some(value.to_string()),
            "Type" if meta.entry_type.is_none() => meta.entry_type = Some(value.to_string()),
            "Hidden" => meta.hidden = value == "true",
            "NoDisplay" => meta.no_display = value == "true",
            _ => {}
        }
    }

    Some(meta)
}

pub fn scan_flatpak_apps(list_file: Option<&Path>) -> Vec<ScannedApp> {
    let lines = if let Some(path) = list_file {
        std::fs::read_to_string(path)
            .unwrap_or_default()
            .lines()
            .map(|l| l.to_string())
            .collect()
    } else {
        run_flatpak_list()
    };

    let mut apps = Vec::new();
    for line in lines {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(app) = parse_flatpak_list_line(line) {
            apps.push(app);
        }
    }
    apps
}

fn run_flatpak_list() -> Vec<String> {
    let output = Command::new("flatpak")
        .args([
            "list",
            "--app",
            "--columns=application,name",
            "--system",
        ])
        .output();
    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(|l| l.to_string())
            .collect(),
        _ => Vec::new(),
    }
}

fn parse_flatpak_list_line(line: &str) -> Option<ScannedApp> {
    let mut parts = line.split('\t');
    let app_id = parts.next()?.trim();
    let name = parts.next().unwrap_or(app_id).trim();
    if app_id.is_empty() {
        return None;
    }
    let id = app_id.to_ascii_lowercase();
    if !crate::validate::validate_id_for_scan(&id) {
        return None;
    }
    let display_name = if name.is_empty() {
        app_id.to_string()
    } else {
        name.to_string()
    };

    Some(ScannedApp {
        id,
        name: display_name,
        kind: AppKind::Flatpak,
        source: AppSource::Flatpak,
        install_path: Some(app_id.to_string()),
        desktop_entry: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn scan_linux_desktop_skips_hidden() {
        let dir = tempdir().unwrap();
        let desktop = dir.path().join("visible-app.desktop");
        std::fs::write(
            &desktop,
            "[Desktop Entry]\nType=Application\nName=Visible\nExec=/usr/bin/visible\n",
        )
        .unwrap();
        let hidden = dir.path().join("hidden-app.desktop");
        std::fs::write(
            &hidden,
            "[Desktop Entry]\nType=Application\nName=Hidden\nExec=/usr/bin/hidden\nHidden=true\n",
        )
        .unwrap();

        let apps = scan_linux_desktop_dir(dir.path());
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].id, "visible-app");
        assert_eq!(apps[0].kind, AppKind::Linux);
    }

    #[test]
    fn scan_flatpak_from_fixture() {
        let dir = tempdir().unwrap();
        let list = dir.path().join("flatpak.list");
        std::fs::write(
            &list,
            "org.gnome.Calculator\tCalculator\ncom.spotify.Client\tSpotify\n",
        )
        .unwrap();

        let apps = scan_flatpak_apps(Some(&list));
        assert_eq!(apps.len(), 2);
        let ids: Vec<_> = apps.iter().map(|a| a.id.as_str()).collect();
        assert!(ids.contains(&"com.spotify.client"));
        assert!(ids.contains(&"org.gnome.calculator"));
        let calc = apps.iter().find(|a| a.id == "org.gnome.calculator").unwrap();
        assert_eq!(calc.source, AppSource::Flatpak);
    }
}
