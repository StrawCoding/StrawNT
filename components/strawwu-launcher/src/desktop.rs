use std::fs;
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
    // Menu shortcuts always pin --backend native (no Wine/Proton env override).
    let exec = format!(
        "{} run --backend native {}",
        desktop_exec_arg(&strawwu),
        desktop_exec_arg(&binary.display().to_string())
    );
    let path = dir.join(format!("{app_id}.desktop"));

    fs::create_dir_all(dir).map_err(|e| e.to_string())?;

    let body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={display_name}\n\
         Comment=Launch with StrawNT (native PE)\n\
         Exec={exec}\n\
         Icon=application-x-ms-dos-executable\n\
         Terminal=false\n\
         Categories=Utility;\n\
         StartupWMClass={app_id}\n\
         X-StrawNT-App-Id={app_id}\n\
         X-StrawNT-Source=launcher\n\
         X-StrawNT-Kind=win32\n\
         X-StrawNT-Backend=native\n"
    );

    fs::write(&path, body).map_err(|e| e.to_string())?;
    Ok(path)
}

const OPEN_HANDLER_ID: &str = "strawnt-open";

const MIME_TYPES: &[&str] = &[
    "application/x-ms-dos-executable",
    "application/x-msdownload",
    "application/vnd.microsoft.portable-executable",
    "application/x-msi",
    "application/x-ms-shortcut",
];

/// Install MIME handler so double-clicking .exe/.msi opens with StrawNT.
pub fn install_desktop_integration() -> Result<PathBuf, String> {
    install_desktop_integration_in(&desktop_dir(), &mime_packages_dir(), &strawwu_bin_for_exec())
}

pub fn install_desktop_integration_in(
    apps_dir: &Path,
    mime_dir: &Path,
    strawwu_bin: &str,
) -> Result<PathBuf, String> {
    fs::create_dir_all(apps_dir).map_err(|e| e.to_string())?;
    fs::create_dir_all(mime_dir).map_err(|e| e.to_string())?;

    let mime_list = MIME_TYPES.join(";");
    let handler = apps_dir.join(format!("{OPEN_HANDLER_ID}.desktop"));
    // Double-click MIME path: strawnt open → native PE only.
    let exec = format!("{} open %f", desktop_exec_arg(strawwu_bin));
    let body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name=StrawNT\n\
         GenericName=Windows App Launcher\n\
         Comment=Install or run Windows .exe/.msi via StrawNT native PE\n\
         Exec={exec}\n\
         TryExec={try_exec}\n\
         Icon=strawnt\n\
         Terminal=false\n\
         Categories=System;Utility;\n\
         MimeType={mime_list};\n\
         NoDisplay=false\n\
         StartupNotify=true\n\
         X-StrawNT-Kind=open-handler\n\
         X-StrawNT-Backend=native\n",
        try_exec = desktop_escape(strawwu_bin),
        mime_list = mime_list,
    );
    fs::write(&handler, body).map_err(|e| e.to_string())?;

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

    Ok(handler)
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
        assert!(content.contains(" run --backend native "));
        assert!(content.contains("X-StrawNT-Backend=native"));
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
        let path = install_desktop_integration_in(
            apps.path(),
            mime.path(),
            "/home/u/.local/bin/strawnt",
        )
        .unwrap();
        assert!(path.exists());
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("MimeType="));
        assert!(content.contains(" open %f"));
        assert!(content.contains("application/x-ms-dos-executable"));
        assert!(content.contains("X-StrawNT-Backend=native"));
        assert!(!content.to_lowercase().contains("wine"));
        assert!(mime.path().join("strawnt-win32.xml").exists());
    }
}
