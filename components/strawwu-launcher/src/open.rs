//! Click-to-open helpers: decide Install vs Run for a double-clicked .exe/.msi.

use std::fs;
use std::path::Path;

use crate::detect::{detect_installer_type, InstallerDetection};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenAction {
    /// Register as installer + launch PE pipeline (desktop launcher written).
    InstallAndRun,
    /// Launch PE pipeline (desktop launcher written).
    Run,
}

/// Heuristic used when the file manager hands an unknown Win32 file to `strawwu open`.
pub fn decide_open_action(path: &Path) -> OpenAction {
    if looks_like_installer(path) {
        OpenAction::InstallAndRun
    } else {
        OpenAction::Run
    }
}

pub fn looks_like_installer(path: &Path) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());
    if ext.as_deref() == Some("msi") {
        return true;
    }

    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    const KEYWORDS: &[&str] = &[
        "setup",
        "install",
        "installer",
        "unins",
        "update",
        "updater",
        "patch",
    ];
    if KEYWORDS.iter().any(|k| name.contains(k)) {
        return true;
    }

    // Peek header when the file exists (best-effort; missing file → not installer).
    let header = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(_) => return false,
    };
    let peek = &header[..header.len().min(8192)];
    !matches!(
        detect_installer_type(peek, path),
        InstallerDetection::Unknown
    )
}

/// Optional desktop notification (no-op when notify-send is unavailable).
pub fn notify(title: &str, body: &str) {
    let _ = std::process::Command::new("notify-send")
        .args(["--app-name=StrawNT", title, body])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn setup_name_is_install() {
        assert!(looks_like_installer(Path::new("/tmp/MyApp-Setup.exe")));
        assert_eq!(
            decide_open_action(Path::new("Setup.exe")),
            OpenAction::InstallAndRun
        );
    }

    #[test]
    fn plain_exe_is_run() {
        assert!(!looks_like_installer(Path::new("/tmp/notepad.exe")));
        assert_eq!(
            decide_open_action(Path::new("game.exe")),
            OpenAction::Run
        );
    }

    #[test]
    fn msi_is_install() {
        assert!(looks_like_installer(Path::new("pkg.msi")));
    }

    #[test]
    fn nsis_magic_detected() {
        let mut f = NamedTempFile::with_suffix(".exe").unwrap();
        let mut buf = vec![0x4D, 0x5A, 0x90, 0x00];
        buf.extend_from_slice(&[0xEF, 0xBE, 0xAD, 0xDE]);
        f.write_all(&buf).unwrap();
        assert!(looks_like_installer(f.path()));
    }
}
