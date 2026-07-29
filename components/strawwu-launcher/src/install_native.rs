//! Native EXE/MSI install path: unpack → app registry → desktop shortcut.
//! Shared by `strawwu install` and `strawwu open` (install mode). No Wine.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;
use strawwu_app_registry::{ExecutionBackend, RegistryStore};
use strawwu_nt::{is_native_installer_blob, unpack_installer_file, UnpackResult};

use crate::desktop;
use crate::registry::{derive_app_id, derive_app_name};

#[derive(Debug, Clone, Serialize)]
pub struct NativeInstallReport {
    pub app_id: String,
    pub app_name: String,
    pub installer: String,
    pub installer_type: String,
    pub install_path: String,
    pub main_exe: String,
    pub files: Vec<String>,
    pub desktop_entry: Option<String>,
    pub backend: String,
    pub mode: String,
    pub package_version: u32,
}

fn apps_root() -> PathBuf {
    if let Ok(dir) = std::env::var("STRAWWU_APPS_DIR") {
        if !dir.is_empty() {
            return PathBuf::from(dir);
        }
    }
    if let Ok(side) = std::env::var("STRAWWU_PE_SIDE_EFFECT_DIR") {
        if !side.is_empty() {
            return PathBuf::from(side).join("apps");
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(".local/share/strawwu/apps");
    }
    PathBuf::from("/var/lib/strawwu/apps")
}

/// True when the on-disk installer carries a StrawWU native SWUP/SWUM archive.
pub fn installer_has_native_package(path: &Path) -> bool {
    match fs::read(path) {
        Ok(data) if !data.is_empty() => is_native_installer_blob(&data),
        _ => false,
    }
}

/// Unpack installer → write registry (Installed) → create .desktop pointing at main.exe.
pub fn native_install(installer: &Path) -> Result<NativeInstallReport, String> {
    let app_id = derive_app_id(installer);
    let app_name = derive_app_name(installer);
    let dest = apps_root().join(&app_id);
    if dest.exists() {
        fs::remove_dir_all(&dest).map_err(|e| format!("clear install root: {e}"))?;
    }
    fs::create_dir_all(&dest).map_err(|e| format!("create install root: {e}"))?;

    let unpacked: UnpackResult = unpack_installer_file(installer, &dest)?;
    let main_exe = unpacked.main_exe.clone();

    let desktop_path = desktop::write_launcher_desktop(&app_id, &main_exe, Some(&app_name))
        .map_err(|e| format!("desktop shortcut: {e}"))?;
    let desktop_entry = desktop_path.to_string_lossy().into_owned();

    let mut store = RegistryStore::open_at(strawwu_app_registry::default_registry_path())
        .map_err(|e| e.to_string())?;
    store
        .finalize_install(
            &app_id,
            &app_name,
            Some(dest.to_string_lossy().into_owned()),
            Some(desktop_entry.clone()),
            Some(ExecutionBackend::Native),
        )
        .map_err(|e| e.to_string())?;

    Ok(NativeInstallReport {
        app_id,
        app_name,
        installer: installer.display().to_string(),
        installer_type: unpacked.installer_type.as_str().to_string(),
        install_path: dest.to_string_lossy().into_owned(),
        main_exe: main_exe.to_string_lossy().into_owned(),
        files: unpacked.files,
        desktop_entry: Some(desktop_entry),
        backend: "native".into(),
        mode: "real".into(),
        package_version: unpacked.package_version,
    })
}
