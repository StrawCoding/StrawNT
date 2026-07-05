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

pub fn write_launcher_desktop(
    app_id: &str,
    binary: &Path,
    name: Option<&str>,
) -> Result<PathBuf, String> {
    let display_name = name
        .map(|s| s.to_string())
        .unwrap_or_else(|| derive_app_name(binary));
    let exec = format!("strawwu run {}", binary.display());
    let path = desktop_path_for(app_id);

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

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
    use std::env;
    use tempfile::tempdir;

    #[test]
    fn write_desktop_entry() {
        let dir = tempdir().unwrap();
        env::set_var("STRAWWU_DESKTOP_DIR", dir.path());
        let binary = Path::new("/tmp/apps/notepad.exe");
        let path = write_launcher_desktop("notepad", binary, Some("Notepad")).unwrap();
        assert!(path.exists());
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("Name=Notepad"));
        assert!(content.contains("X-StrawWU-App-Id=notepad"));
        assert!(content.contains("strawwu run"));
        env::remove_var("STRAWWU_DESKTOP_DIR");
    }
}
