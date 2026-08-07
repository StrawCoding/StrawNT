use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::registry::derive_app_name;

pub fn desktop_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("STRAWNT_DESKTOP_DIR").or_else(|_| std::env::var("STRAWWU_DESKTOP_DIR")) {
        return PathBuf::from(dir);
    }
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(".local/share/applications");
    }
    PathBuf::from("/var/lib/strawnt/applications")
}

pub fn mime_packages_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("STRAWNT_MIME_DIR").or_else(|_| std::env::var("STRAWWU_MIME_DIR")) {
        return PathBuf::from(dir);
    }
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(".local/share/mime/packages");
    }
    PathBuf::from("/var/lib/strawnt/mime/packages")
}

pub fn desktop_path_for(app_id: &str) -> PathBuf {
    desktop_dir().join(format!("{app_id}.desktop"))
}

/// Absolute path to the `strawnt` binary for Exec= lines (desktop envs often have a thin PATH).
pub fn strawwu_bin_for_exec() -> String {
    if let Ok(p) = std::env::var("STRAWNT_BIN").or_else(|_| std::env::var("STRAWWU_BIN")) {
        if !p.is_empty() {
            return p;
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Ok(canon) = exe.canonicalize() {
            return canon.display().to_string();
        }
        return exe.display().to_string();
    }
    if let Ok(prefix) = std::env::var("STRAWNT_PREFIX").or_else(|_| std::env::var("STRAWWU_PREFIX")) {
        for name in ["strawnt-portable", "strawwu-portable", "strawnt", "strawwu"] {
            let candidate = PathBuf::from(&prefix).join("bin").join(name);
            if candidate.is_file() {
                return candidate.display().to_string();
            }
        }
    }
    "strawnt".to_string()
}

/// Reject an app_id that is unsafe as a filename component or .desktop key value.
fn validate_app_id(app_id: &str) -> Result<(), String> {
    if app_id.is_empty() || app_id == "." || app_id == ".." {
        return Err(format!("invalid app_id: {app_id:?}"));
    }
    if !app_id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    {
        return Err(format!(
            "invalid app_id {app_id:?}: only [A-Za-z0-9._-] allowed"
        ));
    }
    Ok(())
}

/// Escape a value per the Desktop Entry spec and drop other control chars.
fn desktop_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => {}
            c => out.push(c),
        }
    }
    out
}

/// Quote a single Exec argument per the Desktop Entry spec.
fn desktop_exec_arg(value: &str) -> String {
    let escaped = desktop_escape(value);
    let mut out = String::with_capacity(escaped.len() + 2);
    out.push('"');
    for c in escaped.chars() {
        if matches!(c, '"' | '`' | '$' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('"');
    out
}

pub fn write_launcher_desktop(
    app_id: &str,
    binary: &Path,
    name: Option<&str>,
) -> Result<PathBuf, String> {
    write_launcher_desktop_in(&desktop_dir(), app_id, binary, name)
}

/// Write a `.desktop` entry into `dir` (tests pass a tempdir; production uses
/// [`desktop_dir`]). Avoids process-global `STRAWWU_DESKTOP_DIR` races under
/// parallel `cargo test`.
pub fn write_launcher_desktop_in(
    dir: &Path,
    app_id: &str,
    binary: &Path,
    name: Option<&str>,
) -> Result<PathBuf, String> {
    validate_app_id(app_id)?;
    let display_name = desktop_escape(
        &name
            .map(|s| s.to_string())
            .unwrap_or_else(|| derive_app_name(binary)),
    );
    let strawwu = strawwu_bin_for_exec();
    // Menu shortcuts pin product default wine (Proton-GE). Legacy: STRAWNT_LEGACY_NATIVE=1.
    let exec = format!(
        "{} run --backend wine {}",
        desktop_exec_arg(&strawwu),
        desktop_exec_arg(&binary.display().to_string())
    );
    let path = dir.join(format!("{app_id}.desktop"));

    fs::create_dir_all(dir).map_err(|e| e.to_string())?;

    let body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={display_name}\n\
         Comment=Launch with StrawNT (Wine/Proton-GE; powered by Wine)\n\
         Exec={exec}\n\
         Icon=application-x-ms-dos-executable\n\
         Terminal=false\n\
         Categories=Utility;\n\
         StartupWMClass={app_id}\n\
         X-StrawNT-App-Id={app_id}\n\
         X-StrawNT-Source=launcher\n\
         X-StrawNT-Kind=win32\n\
         X-StrawNT-Backend=wine\n"
    );

    fs::write(&path, body).map_err(|e| e.to_string())?;
    Ok(path)
}

const MENU_ENTRY_ID: &str = "strawnt";
const OPEN_HANDLER_ID: &str = "strawnt-open";
const LEGACY_OPEN_HANDLER_IDS: &[&str] = &["strawwu-open", "strawwu"];

const MIME_TYPES: &[&str] = &[
    "application/x-ms-dos-executable",
    "application/x-msdownload",
    "application/vnd.microsoft.portable-executable",
    "application/x-msi",
    "application/x-ms-shortcut",
];

/// Result of desktop integration: menu launcher + MIME open handler.
#[derive(Debug, Clone)]
pub struct DesktopIntegration {
    pub menu_entry: PathBuf,
    pub open_handler: PathBuf,
    pub cleared_stale: Vec<PathBuf>,
}

/// Install MIME handler so double-clicking .exe/.msi opens with StrawNT,
/// plus a menu entry that actually launches (status) without requiring %f.
pub fn install_desktop_integration() -> Result<PathBuf, String> {
    let result =
        install_desktop_integration_in(&desktop_dir(), &mime_packages_dir(), &strawwu_bin_for_exec())?;
    Ok(result.menu_entry)
}

pub fn install_desktop_integration_full() -> Result<DesktopIntegration, String> {
    install_desktop_integration_in(&desktop_dir(), &mime_packages_dir(), &strawwu_bin_for_exec())
}

pub fn install_desktop_integration_in(
    apps_dir: &Path,
    mime_dir: &Path,
    strawnt_bin: &str,
) -> Result<DesktopIntegration, String> {
    fs::create_dir_all(apps_dir).map_err(|e| e.to_string())?;
    fs::create_dir_all(mime_dir).map_err(|e| e.to_string())?;

    let cleared_stale = clear_stale_open_handlers(apps_dir, mime_dir);

    let mime_list = MIME_TYPES.join(";");
    let try_exec = desktop_escape(strawnt_bin);
    let bin_exec = desktop_exec_arg(strawnt_bin);

    // App-menu launcher: must work with no %f (users click "StrawNT" in the menu).
    let menu_entry = apps_dir.join(format!("{MENU_ENTRY_ID}.desktop"));
    let menu_body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name=StrawNT\n\
         GenericName=Windows App Runtime\n\
         Comment=StrawNT Wine/Proton-GE runtime (powered by Wine)\n\
         Exec={bin_exec} status\n\
         TryExec={try_exec}\n\
         Icon=strawnt\n\
         Terminal=true\n\
         Categories=System;Utility;\n\
         NoDisplay=false\n\
         StartupNotify=true\n\
         X-StrawNT-Kind=menu-launcher\n\
         X-StrawNT-Backend=wine\n"
    );
    fs::write(&menu_entry, menu_body).map_err(|e| e.to_string())?;

    // MIME / double-click handler — hidden from menus (needs a file argument).
    let open_handler = apps_dir.join(format!("{OPEN_HANDLER_ID}.desktop"));
    let open_exec = format!("{bin_exec} open %f");
    let open_body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name=StrawNT (Open)\n\
         GenericName=Windows App Launcher\n\
         Comment=Install or run Windows .exe/.msi via StrawNT Wine/Proton-GE\n\
         Exec={open_exec}\n\
         TryExec={try_exec}\n\
         Icon=strawnt\n\
         Terminal=false\n\
         Categories=System;Utility;\n\
         MimeType={mime_list};\n\
         NoDisplay=true\n\
         StartupNotify=true\n\
         X-StrawNT-Kind=open-handler\n\
         X-StrawNT-Backend=wine\n"
    );
    fs::write(&open_handler, open_body).map_err(|e| e.to_string())?;

    // Ensure .exe/.msi are recognized even on minimal environments.
    let mime_xml = mime_dir.join("strawnt-win32.xml");
    let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/vnd.microsoft.portable-executable">
    <comment>Windows Portable Executable</comment>
    <glob pattern="*.exe"/>
    <glob pattern="*.dll"/>
  </mime-type>
  <mime-type type="application/x-msi">
    <comment>Windows Installer Package</comment>
    <glob pattern="*.msi"/>
  </mime-type>
</mime-info>
"#;
    fs::write(&mime_xml, xml).map_err(|e| e.to_string())?;

    // Drop legacy StrawWU MIME package if present.
    let legacy_mime = mime_dir.join("strawwu-win32.xml");
    if legacy_mime.exists() {
        let _ = fs::remove_file(&legacy_mime);
    }

    rewrite_mimeapps_defaults_if_applicable(apps_dir, &format!("{OPEN_HANDLER_ID}.desktop"));

    // Best-effort host integration (ignore failures in containers/CI).
    let _ = Command::new("update-desktop-database")
        .arg(apps_dir)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
    if let Some(mime_root) = mime_dir.parent() {
        let _ = Command::new("update-mime-database")
            .arg(mime_root)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
    }
    for mime in MIME_TYPES {
        let _ = Command::new("xdg-mime")
            .args(["default", &format!("{OPEN_HANDLER_ID}.desktop"), mime])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
    }

    Ok(DesktopIntegration {
        menu_entry,
        open_handler,
        cleared_stale,
    })
}

/// Remove legacy StrawWU / temp-path open handlers that steal MIME defaults
/// and make double-click fail (TryExec points at deleted /tmp/.../strawwu).
pub fn clear_stale_open_handlers(apps_dir: &Path, mime_dir: &Path) -> Vec<PathBuf> {
    let mut cleared = Vec::new();

    for id in LEGACY_OPEN_HANDLER_IDS {
        let path = apps_dir.join(format!("{id}.desktop"));
        if path.exists() {
            if fs::remove_file(&path).is_ok() {
                cleared.push(path);
            }
        }
    }

    // Scan remaining .desktop files for broken StrawWU / tmp handlers.
    if let Ok(entries) = fs::read_dir(apps_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if name == format!("{OPEN_HANDLER_ID}.desktop")
                || name == format!("{MENU_ENTRY_ID}.desktop")
            {
                continue;
            }
            let Ok(content) = fs::read_to_string(&path) else {
                continue;
            };
            if should_remove_stale_desktop(&content) {
                if fs::remove_file(&path).is_ok() {
                    cleared.push(path);
                }
            }
        }
    }

    let legacy_mime = mime_dir.join("strawwu-win32.xml");
    if legacy_mime.exists() {
        if fs::remove_file(&legacy_mime).is_ok() {
            cleared.push(legacy_mime);
        }
    }

    cleared
}

fn should_remove_stale_desktop(content: &str) -> bool {
    let lower = content.to_ascii_lowercase();
    let is_open_handler = content.contains("X-StrawWU-Kind=open-handler")
        || content.contains("X-StrawNT-Kind=open-handler")
        || (lower.contains("mimetype=")
            && (lower.contains("application/x-ms-dos-executable")
                || lower.contains("application/x-msi")
                || lower.contains("application/vnd.microsoft.portable-executable")));

    if !is_open_handler {
        // Still remove known-legacy brand handlers even without MimeType.
        if content.contains("Name=StrawWU")
            && (lower.contains("open %f") || lower.contains("strawwu"))
        {
            return tryexec_or_exec_missing(content);
        }
        return false;
    }

    // Prefer removing legacy StrawWU brand handlers always.
    if content.contains("X-StrawWU-Kind=")
        || content.contains("Name=StrawWU")
        || lower.contains("icon=strawwu")
        || lower.contains("/strawwu\"")
        || lower.contains("/strawwu ")
        || lower.contains("tryexec=") && lower.contains("strawwu")
    {
        return true;
    }

    // Remove any open-handler whose TryExec/Exec binary no longer exists
    // (classic failure: /tmp/tmp.*/bin/strawwu after smoke cleanup).
    tryexec_or_exec_missing(content)
}

fn tryexec_or_exec_missing(content: &str) -> bool {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed
            .strip_prefix("TryExec=")
            .or_else(|| trimmed.strip_prefix("Exec="))
        {
            let token = rest
                .trim()
                .trim_matches('"')
                .split_whitespace()
                .next()
                .unwrap_or("");
            if token.is_empty() || token.contains('%') {
                continue;
            }
            // Absolute path that does not exist → stale.
            if token.starts_with('/') && !Path::new(token).exists() {
                return true;
            }
            // Classic tmp smoke leftovers.
            if token.contains("/tmp/") && !Path::new(token).exists() {
                return true;
            }
        }
    }
    false
}

fn rewrite_mimeapps_defaults_if_applicable(apps_dir: &Path, handler_desktop: &str) {
    // Skip when integrating into an isolated temp dir (unit tests), unless forced.
    if std::env::var_os("STRAWNT_FORCE_MIMEAPPS").is_none() {
        let real = desktop_dir();
        if apps_dir != real.as_path() {
            return;
        }
    }
    rewrite_mimeapps_defaults(handler_desktop);
}

fn rewrite_mimeapps_defaults(handler_desktop: &str) {
    let Ok(home) = std::env::var("HOME") else {
        return;
    };
    let config = PathBuf::from(&home).join(".config");
    let _ = fs::create_dir_all(&config);
    let mimeapps = config.join("mimeapps.list");

    let mut lines: Vec<String> = if mimeapps.exists() {
        fs::read_to_string(&mimeapps)
            .unwrap_or_default()
            .lines()
            .map(|s| s.to_string())
            .collect()
    } else {
        Vec::new()
    };

    // Drop associations pointing at legacy handlers.
    lines.retain(|line| {
        let l = line.to_ascii_lowercase();
        !(l.contains("strawwu-open.desktop") || l.contains("=strawwu.desktop"))
    });

    // Ensure [Default Applications] section exists and our MIME types point at StrawNT.
    let mut has_default = lines.iter().any(|l| l.trim() == "[Default Applications]");
    if !has_default {
        if !lines.is_empty() && !lines.last().map(|s| s.is_empty()).unwrap_or(true) {
            lines.push(String::new());
        }
        lines.push("[Default Applications]".to_string());
        has_default = true;
    }
    let _ = has_default;

    for mime in MIME_TYPES {
        let key = format!("{mime}=");
        let replacement = format!("{mime}={handler_desktop}");
        let mut replaced = false;
        for line in lines.iter_mut() {
            if line.trim_start().starts_with(&key) {
                *line = replacement.clone();
                replaced = true;
                break;
            }
        }
        if !replaced {
            // Insert after [Default Applications]
            if let Some(idx) = lines.iter().position(|l| l.trim() == "[Default Applications]") {
                lines.insert(idx + 1, replacement);
            } else {
                lines.push(replacement);
            }
        }
    }

    if let Ok(mut f) = fs::File::create(&mimeapps) {
        let _ = writeln!(f, "{}", lines.join("\n"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn write_desktop_entry() {
        let dir = tempdir().unwrap();
        std::env::set_var("STRAWNT_BIN", "/opt/strawnt/bin/strawnt");
        let binary = Path::new("/tmp/apps/notepad.exe");
        let path =
            write_launcher_desktop_in(dir.path(), "notepad", binary, Some("Notepad")).unwrap();
        assert!(path.exists());
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("Name=Notepad"));
        assert!(content.contains("X-StrawNT-App-Id=notepad"));
        assert!(content.contains("strawnt"));
        assert!(content.contains(" run --backend wine "));
        assert!(content.contains("X-StrawNT-Backend=wine"));
        std::env::remove_var("STRAWNT_BIN");
    }

    #[test]
    fn rejects_app_id_with_path_traversal() {
        let dir = tempdir().unwrap();
        let binary = Path::new("/tmp/apps/x.exe");
        assert!(write_launcher_desktop_in(dir.path(), "../../evil", binary, Some("X")).is_err());
        assert!(write_launcher_desktop_in(dir.path(), "a/b", binary, Some("X")).is_err());
    }

    #[test]
    fn escapes_newline_injection_in_name() {
        let dir = tempdir().unwrap();
        let binary = Path::new("/tmp/apps/x.exe");
        let path = write_launcher_desktop_in(
            dir.path(),
            "safe",
            binary,
            Some("Evil\nExec=/bin/sh -c pwned"),
        )
        .unwrap();
        let content = fs::read_to_string(&path).unwrap();
        assert_eq!(content.matches("\nExec=").count(), 1);
        assert!(content.contains("Name=Evil\\nExec=/bin/sh -c pwned"));
    }

    #[test]
    fn install_open_handler() {
        let apps = tempdir().unwrap();
        let mime = tempdir().unwrap();
        let result = install_desktop_integration_in(
            apps.path(),
            mime.path(),
            "/home/u/.local/bin/strawnt",
        )
        .unwrap();
        assert!(result.menu_entry.exists());
        assert!(result.open_handler.exists());
        let menu = fs::read_to_string(&result.menu_entry).unwrap();
        assert!(menu.contains("Name=StrawNT"));
        assert!(menu.contains(" status"));
        assert!(menu.contains("TryExec=/home/u/.local/bin/strawnt"));
        assert!(!menu.contains(" open %f"));
        let open = fs::read_to_string(&result.open_handler).unwrap();
        assert!(open.contains("MimeType="));
        assert!(open.contains(" open %f"));
        assert!(open.contains("application/x-ms-dos-executable"));
        assert!(open.contains("X-StrawNT-Backend=wine"));
        assert!(open.contains("NoDisplay=true"));
        assert!(open.to_lowercase().contains("wine"));
        assert!(open.to_lowercase().contains("powered by wine") || open.contains("Proton-GE") || open.contains("Wine"));
        assert!(mime.path().join("strawnt-win32.xml").exists());
    }

    #[test]
    fn clears_stale_strawwu_tmp_handler() {
        let apps = tempdir().unwrap();
        let mime = tempdir().unwrap();
        let stale = apps.path().join("strawwu-open.desktop");
        fs::write(
            &stale,
            r#"[Desktop Entry]
Type=Application
Name=StrawWU
Exec="/tmp/tmp.hqa8qM1Rum/bin/strawwu" open %f
TryExec=/tmp/tmp.hqa8qM1Rum/bin/strawwu
MimeType=application/x-ms-dos-executable;application/x-msi;
X-StrawWU-Kind=open-handler
"#,
        )
        .unwrap();
        let legacy_mime = mime.path().join("strawwu-win32.xml");
        fs::write(&legacy_mime, "<mime-info/>").unwrap();

        let result = install_desktop_integration_in(
            apps.path(),
            mime.path(),
            "/home/u/.local/bin/strawnt",
        )
        .unwrap();
        assert!(!stale.exists(), "stale strawwu-open.desktop must be removed");
        assert!(!legacy_mime.exists(), "legacy strawwu MIME xml must be removed");
        assert!(
            result
                .cleared_stale
                .iter()
                .any(|p| p.file_name().and_then(|n| n.to_str()) == Some("strawwu-open.desktop")),
            "cleared_stale should report strawwu-open.desktop"
        );
        assert!(result.menu_entry.exists());
        assert!(result.open_handler.exists());
    }

    #[test]
    fn should_remove_detects_missing_tryexec() {
        let body = r#"[Desktop Entry]
Name=Broken
TryExec=/tmp/does-not-exist-strawwu-xyz/bin/strawwu
Exec="/tmp/does-not-exist-strawwu-xyz/bin/strawwu" open %f
MimeType=application/x-ms-dos-executable;
X-StrawWU-Kind=open-handler
"#;
        assert!(should_remove_stale_desktop(body));
    }
}
