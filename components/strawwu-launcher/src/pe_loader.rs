use std::fs;
use std::path::Path;

use strawwu_nt::pe::{build_stub_pe, PeMachine, PeSubsystem};

use crate::detect::{detect_format, BinaryFormat};

/// Load PE bytes from disk, or synthesize a GUI stub for smoke when path is absent.
pub fn load_pe_bytes(path: &Path, format: BinaryFormat) -> Result<Vec<u8>, String> {
    if path.exists() {
        let data = fs::read(path).map_err(|e| e.to_string())?;
        if !data.is_empty() && detect_format(&data) != BinaryFormat::Unknown {
            return Ok(data);
        }
    }

    if format == BinaryFormat::PE {
        Ok(build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui))
    } else {
        Err(format!(
            "cannot load PE for {} (format={})",
            path.display(),
            format.as_str()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn stub_pe_for_missing_exe() {
        let path = PathBuf::from("/nonexistent/notepad.exe");
        let data = load_pe_bytes(&path, BinaryFormat::PE).unwrap();
        assert!(data.len() > 64);
        assert_eq!(detect_format(&data), BinaryFormat::PE);
    }
}
