use std::path::Path;

const PE_MAGIC: [u8; 2] = [0x4D, 0x5A]; // MZ
const ELF_MAGIC: [u8; 4] = [0x7F, 0x45, 0x4C, 0x46]; // \x7FELF

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryFormat {
    PE,
    ELF,
    Unknown,
}

impl BinaryFormat {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::PE => "PE",
            Self::ELF => "ELF",
            Self::Unknown => "unknown",
        }
    }

    pub fn is_windows(&self) -> bool {
        matches!(self, Self::PE)
    }

    pub fn is_linux(&self) -> bool {
        matches!(self, Self::ELF)
    }
}

pub fn detect_format(header: &[u8]) -> BinaryFormat {
    if header.len() >= 4 && header[..4] == ELF_MAGIC {
        BinaryFormat::ELF
    } else if header.len() >= 2 && header[..2] == PE_MAGIC {
        BinaryFormat::PE
    } else {
        BinaryFormat::Unknown
    }
}

const NSIS_MAGIC: &[u8] = &[0xEF, 0xBE, 0xAD, 0xDE];
const INNO_MARKER: &[u8] = b"Inno Setup";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallerDetection {
    Nsis,
    InnoSetup,
    Msi,
    WixBurn,
    Unknown,
}

pub fn detect_installer_type(header: &[u8], path: &Path) -> InstallerDetection {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    if ext.as_deref() == Some("msi") {
        return InstallerDetection::Msi;
    }

    if header.len() >= 4 && header.windows(4).any(|w| w == NSIS_MAGIC) {
        return InstallerDetection::Nsis;
    }

    if header.windows(INNO_MARKER.len()).any(|w| w == INNO_MARKER) {
        return InstallerDetection::InnoSetup;
    }

    // WiX Burn bundles embed a ".wixburn" section marker
    if header.windows(8).any(|w| w == b".wixburn") {
        return InstallerDetection::WixBurn;
    }

    InstallerDetection::Unknown
}

const DOTNET_DLLS: &[&str] = &["mscoree.dll", "clrjit.dll", "coreclr.dll", "mscorlib.dll"];

pub fn detect_dotnet_dependency(imports: &[(&str, &[&str])]) -> bool {
    imports.iter().any(|(dll, _)| {
        let lower = dll.to_lowercase();
        DOTNET_DLLS.iter().any(|d| lower == *d)
    })
}

const VCREDIST_DLLS: &[&str] = &[
    "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll",
    "msvcp120.dll", "msvcr120.dll",
    "msvcp110.dll", "msvcr110.dll",
    "msvcp100.dll", "msvcr100.dll",
];

pub fn detect_vcredist_dependency(imports: &[(&str, &[&str])]) -> bool {
    imports.iter().any(|(dll, _)| {
        let lower = dll.to_lowercase();
        VCREDIST_DLLS.iter().any(|v| lower == *v)
    })
}

pub fn detect_from_path(path: &Path) -> std::io::Result<BinaryFormat> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase());

    match ext.as_deref() {
        Some("exe") | Some("dll") | Some("msi") => Ok(BinaryFormat::PE),
        Some("so") | Some("bin") => Ok(BinaryFormat::ELF),
        _ => {
            if path.exists() {
                let data = std::fs::read(path)?;
                Ok(detect_format(&data))
            } else {
                Ok(BinaryFormat::Unknown)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detect_pe_header() {
        let header = [0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00];
        assert_eq!(detect_format(&header), BinaryFormat::PE);
        assert!(detect_format(&header).is_windows());
    }

    #[test]
    fn detect_elf_header() {
        let header = [0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01];
        assert_eq!(detect_format(&header), BinaryFormat::ELF);
        assert!(detect_format(&header).is_linux());
    }

    #[test]
    fn detect_unknown() {
        let header = [0x00, 0x01, 0x02, 0x03];
        assert_eq!(detect_format(&header), BinaryFormat::Unknown);
    }

    #[test]
    fn detect_from_extension() {
        let path = Path::new("/fake/game.exe");
        let fmt = detect_from_path(path).unwrap();
        assert_eq!(fmt, BinaryFormat::PE);
    }

    #[test]
    fn format_str() {
        assert_eq!(BinaryFormat::PE.as_str(), "PE");
        assert_eq!(BinaryFormat::ELF.as_str(), "ELF");
    }

    #[test]
    fn detect_nsis_installer() {
        let mut header = vec![0x4D, 0x5A, 0x90, 0x00]; // MZ
        header.extend_from_slice(&[0xEF, 0xBE, 0xAD, 0xDE]); // NSIS magic
        assert_eq!(
            detect_installer_type(&header, Path::new("setup.exe")),
            InstallerDetection::Nsis
        );
    }

    #[test]
    fn detect_msi_by_extension() {
        assert_eq!(
            detect_installer_type(&[], Path::new("package.msi")),
            InstallerDetection::Msi
        );
    }

    #[test]
    fn detect_dotnet_from_imports() {
        let imports: Vec<(&str, &[&str])> = vec![
            ("kernel32.dll", &["LoadLibraryA"]),
            ("mscoree.dll", &["_CorExeMain"]),
        ];
        assert!(detect_dotnet_dependency(&imports));

        let no_dotnet: Vec<(&str, &[&str])> = vec![
            ("kernel32.dll", &["LoadLibraryA"]),
        ];
        assert!(!detect_dotnet_dependency(&no_dotnet));
    }

    #[test]
    fn detect_vcredist_from_imports() {
        let imports: Vec<(&str, &[&str])> = vec![
            ("VCRUNTIME140.dll", &["memcpy"]),
            ("kernel32.dll", &["GetProcAddress"]),
        ];
        assert!(detect_vcredist_dependency(&imports));

        let no_vcredist: Vec<(&str, &[&str])> = vec![
            ("kernel32.dll", &["GetProcAddress"]),
        ];
        assert!(!detect_vcredist_dependency(&no_vcredist));
    }
}
