//! Native EXE/MSI installer package format (no Wine).
//!
//! StrawWU Portable packages embed a length-prefixed file table that the
//! host-side installer unpacks into an app install root. EXE installers are
//! self-extracting PE stubs with a trailing `SWUP` archive; MSI packages use a
//! `SWUM` archive (optionally prefixed with the OLE compound-file magic so the
//! file is recognisable as an MSI-class blob).

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::pe::{build_win32_console_mvp_pe, PeMachine};

/// Magic for EXE self-extracting trailer archives.
pub const SWUP_MAGIC: &[u8; 4] = b"SWUP";
/// Magic for MSI-class native archives.
pub const SWUM_MAGIC: &[u8; 4] = b"SWUM";
/// OLE compound-file magic (classic MSI container signature).
pub const OLE_CFB_MAGIC: &[u8; 8] = &[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

const PACKAGE_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstallerType {
    Exe,
    Msi,
    Unknown,
}

impl InstallerType {
    pub fn detect(path: &str) -> Self {
        let lower = path.to_lowercase();
        if lower.ends_with(".msi") {
            Self::Msi
        } else if lower.ends_with(".exe") {
            Self::Exe
        } else {
            Self::Unknown
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Exe => "exe",
            Self::Msi => "msi",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstallState {
    Pending,
    Installing,
    Installed,
    Failed,
    Repaired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageFile {
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NativePackage {
    pub version: u32,
    pub files: Vec<PackageFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnpackResult {
    pub installer_type: InstallerType,
    pub install_path: PathBuf,
    pub files: Vec<String>,
    pub main_exe: PathBuf,
    pub package_version: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstalledApp {
    pub app_id: String,
    pub display_name: String,
    pub install_path: String,
    pub installer_type: InstallerType,
    pub state: InstallState,
    pub machine: String,
    pub files: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileSnapshot {
    pub app_id: String,
    pub timestamp: String,
    pub registry_keys: HashMap<String, String>,
    pub file_list: Vec<String>,
    pub install_path: String,
}

impl ProfileSnapshot {
    pub fn capture(app: &InstalledApp) -> Self {
        Self {
            app_id: app.app_id.clone(),
            timestamp: "2026-07-04T00:00:00Z".to_string(),
            registry_keys: HashMap::new(),
            file_list: app.files.clone(),
            install_path: app.install_path.clone(),
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AppDatabase {
    apps: HashMap<String, InstalledApp>,
    snapshots: HashMap<String, ProfileSnapshot>,
}

impl AppDatabase {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn install(
        &mut self,
        app_id: &str,
        display_name: &str,
        path: &str,
        installer_type: InstallerType,
    ) -> &InstalledApp {
        let app = InstalledApp {
            app_id: app_id.to_string(),
            display_name: display_name.to_string(),
            install_path: path.to_string(),
            installer_type,
            state: InstallState::Installed,
            machine: PeMachine::Amd64.as_str().to_string(),
            files: vec![format!("{}/main.exe", path)],
        };
        self.apps.insert(app_id.to_string(), app);
        self.apps.get(app_id).unwrap()
    }

    pub fn get(&self, app_id: &str) -> Option<&InstalledApp> {
        self.apps.get(app_id)
    }

    pub fn list(&self) -> Vec<&InstalledApp> {
        self.apps.values().collect()
    }

    pub fn repair(&mut self, app_id: &str) -> Result<(), String> {
        if let Some(snap) = self.snapshots.get(app_id) {
            if let Some(app) = self.apps.get_mut(app_id) {
                app.files = snap.file_list.clone();
                app.state = InstallState::Repaired;
                return Ok(());
            }
        }
        if let Some(app) = self.apps.get_mut(app_id) {
            app.state = InstallState::Repaired;
            return Ok(());
        }
        Err(format!("app not found: {}", app_id))
    }

    pub fn snapshot(&mut self, app_id: &str) -> Result<(), String> {
        if let Some(app) = self.apps.get(app_id) {
            let snap = ProfileSnapshot::capture(app);
            self.snapshots.insert(app_id.to_string(), snap);
            Ok(())
        } else {
            Err(format!("app not found: {}", app_id))
        }
    }

    pub fn get_snapshot(&self, app_id: &str) -> Option<&ProfileSnapshot> {
        self.snapshots.get(app_id)
    }

    pub fn app_count(&self) -> usize {
        self.apps.len()
    }
}

fn encode_archive(magic: &[u8; 4], package: &NativePackage) -> Result<Vec<u8>, String> {
    if package.version != PACKAGE_VERSION {
        return Err(format!("unsupported package version {}", package.version));
    }
    let mut out = Vec::new();
    out.extend_from_slice(magic);
    out.extend_from_slice(&package.version.to_le_bytes());
    out.extend_from_slice(&(package.files.len() as u32).to_le_bytes());
    for file in &package.files {
        validate_relative_name(&file.name)?;
        let name_bytes = file.name.as_bytes();
        if name_bytes.len() > u16::MAX as usize {
            return Err(format!("file name too long: {}", file.name));
        }
        out.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
        out.extend_from_slice(name_bytes);
        out.extend_from_slice(&(file.data.len() as u32).to_le_bytes());
        out.extend_from_slice(&file.data);
    }
    // Footer: magic echo + archive byte length (from magic through end of this u32).
    let archive_len = (out.len() + magic.len() + 4) as u32;
    out.extend_from_slice(magic);
    out.extend_from_slice(&archive_len.to_le_bytes());
    Ok(out)
}

fn decode_archive(data: &[u8], magic: &[u8; 4]) -> Result<NativePackage, String> {
    if data.len() < 12 {
        return Err("archive too short".into());
    }
    if &data[0..4] != magic {
        return Err(format!(
            "bad archive magic (expected {})",
            String::from_utf8_lossy(magic)
        ));
    }
    let version = u32::from_le_bytes(data[4..8].try_into().unwrap());
    if version != PACKAGE_VERSION {
        return Err(format!("unsupported package version {version}"));
    }
    let file_count = u32::from_le_bytes(data[8..12].try_into().unwrap()) as usize;
    let mut offset = 12usize;
    let mut files = Vec::with_capacity(file_count);
    for _ in 0..file_count {
        if offset + 2 > data.len() {
            return Err("truncated name length".into());
        }
        let name_len = u16::from_le_bytes(data[offset..offset + 2].try_into().unwrap()) as usize;
        offset += 2;
        if offset + name_len + 4 > data.len() {
            return Err("truncated file name/data length".into());
        }
        let name = String::from_utf8(data[offset..offset + name_len].to_vec())
            .map_err(|e| format!("invalid utf8 file name: {e}"))?;
        validate_relative_name(&name)?;
        offset += name_len;
        let data_len = u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap()) as usize;
        offset += 4;
        if offset + data_len > data.len() {
            return Err(format!("truncated file data for {name}"));
        }
        let file_data = data[offset..offset + data_len].to_vec();
        offset += data_len;
        files.push(PackageFile {
            name,
            data: file_data,
        });
    }
    Ok(NativePackage {
        version,
        files,
    })
}

fn validate_relative_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("empty file name".into());
    }
    if name.starts_with('/') || name.starts_with('\\') {
        return Err(format!("absolute path rejected: {name}"));
    }
    for part in name.split(['/', '\\']) {
        if part.is_empty() || part == "." || part == ".." {
            return Err(format!("unsafe path component in {name}"));
        }
    }
    Ok(())
}

/// Locate a trailing SWUP archive appended to a PE stub.
pub fn find_swup_trailer(data: &[u8]) -> Option<usize> {
    if data.len() < 8 {
        return None;
    }
    let len_bytes = &data[data.len() - 4..];
    let archive_len = u32::from_le_bytes(len_bytes.try_into().ok()?) as usize;
    if archive_len < 12 || archive_len > data.len() {
        return None;
    }
    let start = data.len() - archive_len;
    if &data[start..start + 4] != SWUP_MAGIC {
        return None;
    }
    let footer_magic = &data[data.len() - 8..data.len() - 4];
    if footer_magic != SWUP_MAGIC {
        return None;
    }
    Some(start)
}

/// Parse a native package from EXE SFX or MSI-class bytes.
pub fn parse_native_package(data: &[u8]) -> Result<(InstallerType, NativePackage), String> {
    if let Some(start) = find_swup_trailer(data) {
        let package = decode_archive(&data[start..], SWUP_MAGIC)?;
        return Ok((InstallerType::Exe, package));
    }

    let body = if data.starts_with(OLE_CFB_MAGIC) {
        &data[OLE_CFB_MAGIC.len()..]
    } else {
        data
    };
    if body.starts_with(SWUM_MAGIC) {
        // Strip footer for decode: encode_archive appends magic+len.
        let package = decode_archive(body, SWUM_MAGIC)?;
        return Ok((InstallerType::Msi, package));
    }

    Err("no StrawWU native installer archive (SWUP/SWUM) found".into())
}

/// Build an EXE self-extracting installer: PE stub + SWUP trailer with files.
pub fn build_sfx_installer(stub_pe: &[u8], files: Vec<PackageFile>) -> Result<Vec<u8>, String> {
    if stub_pe.len() < 2 || stub_pe[0] != 0x4D || stub_pe[1] != 0x5A {
        return Err("stub must be a PE (MZ)".into());
    }
    let archive = encode_archive(
        SWUP_MAGIC,
        &NativePackage {
            version: PACKAGE_VERSION,
            files,
        },
    )?;
    let mut out = stub_pe.to_vec();
    out.extend_from_slice(&archive);
    Ok(out)
}

/// Build an MSI-class native package (OLE magic + SWUM archive).
pub fn build_msi_package(files: Vec<PackageFile>) -> Result<Vec<u8>, String> {
    let archive = encode_archive(
        SWUM_MAGIC,
        &NativePackage {
            version: PACKAGE_VERSION,
            files,
        },
    )?;
    let mut out = OLE_CFB_MAGIC.to_vec();
    out.extend_from_slice(&archive);
    Ok(out)
}

/// pe4 fixture helpers: SFX + MSI wrapping the console MVP as `main.exe`.
pub fn build_pe4_installer_fixtures() -> Result<(Vec<u8>, Vec<u8>), String> {
    let main = build_win32_console_mvp_pe();
    let marker = b"STRAWWU_PE4_INSTALLED\n".to_vec();
    let files = vec![
        PackageFile {
            name: "main.exe".into(),
            data: main.clone(),
        },
        PackageFile {
            name: "STRAWWU_INSTALL.txt".into(),
            data: marker,
        },
    ];
    // Stub PE is itself the console MVP — running it yields mode=real side effects.
    let sfx = build_sfx_installer(&main, files.clone())?;
    let msi = build_msi_package(files)?;
    Ok((sfx, msi))
}

fn prefer_main_exe(files: &[PackageFile]) -> Result<String, String> {
    if files.iter().any(|f| f.name == "main.exe") {
        return Ok("main.exe".into());
    }
    files
        .iter()
        .find(|f| f.name.to_lowercase().ends_with(".exe"))
        .map(|f| f.name.clone())
        .ok_or_else(|| "package has no .exe payload".to_string())
}

/// Unpack a native installer blob into `dest_dir`.
pub fn unpack_native_package(data: &[u8], dest_dir: &Path) -> Result<UnpackResult, String> {
    let (installer_type, package) = parse_native_package(data)?;
    let main_name = prefer_main_exe(&package.files)?;
    fs::create_dir_all(dest_dir).map_err(|e| e.to_string())?;

    let mut written = Vec::new();
    for file in &package.files {
        let target = dest_dir.join(&file.name);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::write(&target, &file.data).map_err(|e| format!("write {}: {e}", target.display()))?;
        written.push(file.name.clone());
    }

    let main_exe = dest_dir.join(&main_name);
    if !main_exe.is_file() {
        return Err(format!("main exe missing after unpack: {}", main_exe.display()));
    }

    Ok(UnpackResult {
        installer_type,
        install_path: dest_dir.to_path_buf(),
        files: written,
        main_exe,
        package_version: package.version,
    })
}

/// Unpack installer file from disk into `dest_dir`.
pub fn unpack_installer_file(path: &Path, dest_dir: &Path) -> Result<UnpackResult, String> {
    let data = fs::read(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    unpack_native_package(&data, dest_dir)
}

/// True when bytes contain a StrawWU native installer archive.
pub fn is_native_installer_blob(data: &[u8]) -> bool {
    parse_native_package(data).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn installer_type_detection() {
        assert_eq!(InstallerType::detect("setup.exe"), InstallerType::Exe);
        assert_eq!(InstallerType::detect("app.msi"), InstallerType::Msi);
        assert_eq!(InstallerType::detect("readme.txt"), InstallerType::Unknown);
    }

    #[test]
    fn app_install_and_list() {
        let mut db = AppDatabase::new();
        db.install(
            "notepad",
            "Notepad++",
            r"C:\Program Files\Notepad++",
            InstallerType::Exe,
        );
        assert_eq!(db.app_count(), 1);
        assert!(db.get("notepad").is_some());
        assert_eq!(db.get("notepad").unwrap().state, InstallState::Installed);
    }

    #[test]
    fn app_snapshot_and_repair() {
        let mut db = AppDatabase::new();
        db.install("test-app", "Test App", r"C:\Apps\Test", InstallerType::Exe);
        db.snapshot("test-app").unwrap();
        assert!(db.get_snapshot("test-app").is_some());
        db.repair("test-app").unwrap();
        assert_eq!(db.get("test-app").unwrap().state, InstallState::Repaired);
    }

    #[test]
    fn repair_nonexistent_fails() {
        let mut db = AppDatabase::new();
        assert!(db.repair("nonexistent").is_err());
    }

    #[test]
    fn snapshot_nonexistent_fails() {
        let mut db = AppDatabase::new();
        assert!(db.snapshot("nonexistent").is_err());
    }

    #[test]
    fn sfx_roundtrip_unpacks_main_exe() {
        let files = vec![
            PackageFile {
                name: "main.exe".into(),
                data: b"MZ-fake-pe".to_vec(),
            },
            PackageFile {
                name: "readme.txt".into(),
                data: b"hi".to_vec(),
            },
        ];
        let stub = {
            let mut pe = vec![0u8; 64];
            pe[0] = 0x4D;
            pe[1] = 0x5A;
            pe
        };
        let sfx = build_sfx_installer(&stub, files).unwrap();
        assert!(find_swup_trailer(&sfx).is_some());

        let dir = std::env::temp_dir().join(format!(
            "strawwu-pe4-sfx-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        let result = unpack_native_package(&sfx, &dir).unwrap();
        assert_eq!(result.installer_type, InstallerType::Exe);
        assert_eq!(result.files.len(), 2);
        assert!(result.main_exe.is_file());
        assert_eq!(fs::read(dir.join("readme.txt")).unwrap(), b"hi");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn msi_roundtrip_with_ole_prefix() {
        let files = vec![PackageFile {
            name: "main.exe".into(),
            data: b"MZ-main".to_vec(),
        }];
        let msi = build_msi_package(files).unwrap();
        assert!(msi.starts_with(OLE_CFB_MAGIC));
        assert!(is_native_installer_blob(&msi));

        let dir = std::env::temp_dir().join(format!(
            "strawwu-pe4-msi-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        let result = unpack_native_package(&msi, &dir).unwrap();
        assert_eq!(result.installer_type, InstallerType::Msi);
        assert_eq!(fs::read(&result.main_exe).unwrap(), b"MZ-main");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_path_traversal() {
        let files = vec![PackageFile {
            name: "../evil.exe".into(),
            data: b"x".to_vec(),
        }];
        assert!(build_msi_package(files).is_err());
    }

    #[test]
    fn pe4_fixtures_parse() {
        let (sfx, msi) = build_pe4_installer_fixtures().unwrap();
        assert!(is_native_installer_blob(&sfx));
        assert!(is_native_installer_blob(&msi));
        let (t1, p1) = parse_native_package(&sfx).unwrap();
        let (t2, p2) = parse_native_package(&msi).unwrap();
        assert_eq!(t1, InstallerType::Exe);
        assert_eq!(t2, InstallerType::Msi);
        assert!(p1.files.iter().any(|f| f.name == "main.exe"));
        assert!(p2.files.iter().any(|f| f.name == "STRAWWU_INSTALL.txt"));
    }
}
