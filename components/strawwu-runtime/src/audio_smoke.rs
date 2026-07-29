//! Portable GX1 audio/input smoke — WASAPI→PipeWire/equivalent + XInput via strawwu-audio.

use std::path::Path;

pub use strawwu_audio::{run_audio_input_smoke, AudioInputSmokeResult};

/// Run the portable audio/input smoke into `out_dir`.
pub fn run_portable_audio_input_smoke(out_dir: &Path) -> Result<AudioInputSmokeResult, String> {
    run_audio_input_smoke(out_dir).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn portable_audio_input_smoke_pass() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("strawwu-rt-gx1-{stamp}"));
        let result = run_portable_audio_input_smoke(&dir).unwrap();
        assert!(result.status == "PASS" || result.status == "PARTIAL");
        assert_eq!(result.execution_backend, "native");
        assert!(result.bytes_rendered > 44);
        assert!(result.input.controllers_connected >= 1);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
