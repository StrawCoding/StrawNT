use std::fs;
use std::path::Path;

use strawwu_nt::pe::{build_stub_pe, PeMachine, PeSubsystem};

use crate::detect::{detect_format, BinaryFormat};

/// True when the caller explicitly opted into smoke/simulation mode.
///
/// Synthesizing a stub PE for a missing/invalid binary is only acceptable for
/// wiring smoke tests that exercise the launcher/registry/desktop path without a
/// real Windows binary. In normal use a missing or invalid file must be a hard
/// error so `strawwu run /missing.exe` never reports a fake success.
pub fn smoke_mode() -> bool {
    matches!(std::env::var("STRAWWU_SMOKE").as_deref(), Ok("1"))
}

/// Load PE bytes from disk. Returns an error for a missing/invalid binary unless
/// smoke mode (`STRAWWU_SMOKE=1`) is set, in which case a stub PE is synthesized
/// for wiring smoke tests.
pub fn load_pe_bytes(path: &Path, format: BinaryFormat) -> Result<Vec<u8>, String> {
    if path.exists() {
        let data = fs::read(path).map_err(|e| e.to_string())?;
        if !data.is_empty() && detect_format(&data) != BinaryFormat::Unknown {
            return Ok(data);
        }
        if !smoke_mode() {
            return Err(format!(
                "invalid or empty binary: {} (not a recognized PE/ELF/MSI)",
                path.display()
            ));
        }
    } else if !smoke_mode() {
        return Err(format!("binary not found: {}", path.display()));
    }

    if format == BinaryFormat::PE {
        // smoke_mode() is guaranteed true here.
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
    fn stub_pe_for_missing_exe_in_smoke_mode() {
        std::env::set_var("STRAWWU_SMOKE", "1");
        let path = PathBuf::from("/nonexistent/notepad.exe");
        let data = load_pe_bytes(&path, BinaryFormat::PE).unwrap();
        assert!(data.len() > 64);
        assert_eq!(detect_format(&data), BinaryFormat::PE);
        std::env::remove_var("STRAWWU_SMOKE");
    }

    #[test]
    fn missing_exe_errors_without_smoke() {
        std::env::remove_var("STRAWWU_SMOKE");
        let path = PathBuf::from("/nonexistent/notepad.exe");
        assert!(load_pe_bytes(&path, BinaryFormat::PE).is_err());
    }
}
