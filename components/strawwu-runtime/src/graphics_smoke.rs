//! Portable GX0 graphics smoke — DXGI/D3D11→VK + wgl→GL/present via strawwu-graphics.

use std::path::Path;

pub use strawwu_graphics::{run_graphics_smoke, GraphicsSmokeResult};

/// Run the portable graphics triangle/present smoke into `out_dir`.
pub fn run_portable_graphics_smoke(
    out_dir: &Path,
    width: u32,
    height: u32,
) -> Result<GraphicsSmokeResult, String> {
    run_graphics_smoke(out_dir, width, height).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn portable_graphics_smoke_pass() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("strawwu-rt-gx0-{stamp}"));
        let result = run_portable_graphics_smoke(&dir, 320, 240).unwrap();
        assert_eq!(result.status, "PASS");
        assert_eq!(result.execution_backend, "native");
        assert!(result.triangle_pixels > 100);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
