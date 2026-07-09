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
/// `smoke` is true, in which case a stub PE is synthesized for wiring smoke tests.
///
/// `smoke` is passed explicitly (production resolves it once via [`smoke_mode`])
/// rather than read from the process environment here: reading a global env var
/// inside the function made the unit tests race on `STRAWWU_SMOKE` when run in
/// parallel (one test setting it while another cleared it).
pub fn load_pe_bytes(path: &Path, format: BinaryFormat, smoke: bool) -> Result<Vec<u8>, String> {
    if path.exists() {
        let data = fs::read(path).map_err(|e| e.to_string())?;
        if !data.is_empty() && detect_format(&data) != BinaryFormat::Unknown {
            return Ok(data);
        }
        if !smoke {
            return Err(format!(
                "invalid or empty binary: {} (not a recognized PE/ELF/MSI)",
                path.display()
            ));
        }
    } else if !smoke {
        return Err(format!("binary not found: {}", path.display()));
    }

    if format == BinaryFormat::PE {
        // smoke is guaranteed true here.
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
        let path = PathBuf::from("/nonexistent/notepad.exe");
        let data = load_pe_bytes(&path, BinaryFormat::PE, true).unwrap();
        assert!(data.len() > 64);
        assert_eq!(detect_format(&data), BinaryFormat::PE);
    }

    #[test]
    fn missing_exe_errors_without_smoke() {
        let path = PathBuf::from("/nonexistent/notepad.exe");
        assert!(load_pe_bytes(&path, BinaryFormat::PE, false).is_err());
    }
}
