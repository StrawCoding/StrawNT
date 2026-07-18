use std::fs;
use std::path::{Path, PathBuf};

use crate::registry::derive_app_name;

pub fn desktop_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("STRAWWU_DESKTOP_DIR") {
        return PathBuf::from(dir);
    }
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(".local/share/applications");
    }
    PathBuf::from("/var/lib/strawwu/applications")
}

pub fn desktop_path_for(app_id: &str) -> PathBuf {
    desktop_dir().join(format!("{app_id}.desktop"))
}

/// Reject an app_id that is unsafe as a filename component or .desktop key value.
/// app_id becomes the `<app_id>.desktop` filename and several key values, so a
/// value with path separators (traversal) or control chars (line injection) must
/// never reach the filesystem or the file body.
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

/// Escape a value per the Desktop Entry spec and drop other control chars so a
/// crafted app name or binary path cannot inject extra keys/lines.
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

/// Quote a single Exec argument per the Desktop Entry spec (double-quoted, with
/// reserved chars backslash-escaped) after control-char escaping.
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
    let exec = format!("strawwu run {}", desktop_exec_arg(&binary.display().to_string()));
    let path = dir.join(format!("{app_id}.desktop"));

    fs::create_dir_all(dir).map_err(|e| e.to_string())?;

    let body = format!(
        "[Desktop Entry]\n\
         Type=Application\n\
         Name={display_name}\n\
         Exec={exec}\n\
         Icon=application-x-ms-dos-executable\n\
         Terminal=false\n\
         Categories=Utility;\n\
         StartupWMClass={app_id}\n\
         X-StrawWU-App-Id={app_id}\n\
         X-StrawWU-Source=launcher\n\
         X-StrawWU-Kind=win32\n"
    );

    fs::write(&path, body).map_err(|e| e.to_string())?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn write_desktop_entry() {
        let dir = tempdir().unwrap();
        let binary = Path::new("/tmp/apps/notepad.exe");
        let path = write_launcher_desktop_in(dir.path(), "notepad", binary, Some("Notepad")).unwrap();
        assert!(path.exists());
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("Name=Notepad"));
        assert!(content.contains("X-StrawWU-App-Id=notepad"));
        assert!(content.contains("strawwu run"));
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
        // The injected newline must not create a second Exec line.
        assert_eq!(content.matches("\nExec=").count(), 1);
        assert!(content.contains("Name=Evil\\nExec=/bin/sh -c pwned"));
    }
}
