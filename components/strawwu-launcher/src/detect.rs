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
}
