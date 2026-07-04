use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DisplayBackend {
    Wayland,
    X11,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VsyncMode {
    Off,
    On,
    Adaptive,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PresentBridge {
    pub display_backend: DisplayBackend,
    pub vsync: VsyncMode,
    pub fullscreen: bool,
    pub width: u32,
    pub height: u32,
    pub frame_count: u64,
}

impl PresentBridge {
    pub fn new(backend: DisplayBackend) -> Self {
        Self {
            display_backend: backend,
            vsync: VsyncMode::On,
            fullscreen: false,
            width: 1920,
            height: 1080,
            frame_count: 0,
        }
    }

    pub fn present_frame(&mut self) -> Result<(), PresentError> {
        self.frame_count += 1;
        Ok(())
    }

    pub fn set_resolution(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
    }

    pub fn set_fullscreen(&mut self, fullscreen: bool) {
        self.fullscreen = fullscreen;
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum PresentError {
    #[error("display surface lost")]
    SurfaceLost,
    #[error("present failed")]
    PresentFailed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn present_bridge_creation() {
        let bridge = PresentBridge::new(DisplayBackend::Wayland);
        assert_eq!(bridge.display_backend, DisplayBackend::Wayland);
        assert_eq!(bridge.frame_count, 0);
    }

    #[test]
    fn present_frame() {
        let mut bridge = PresentBridge::new(DisplayBackend::X11);
        bridge.present_frame().unwrap();
        bridge.present_frame().unwrap();
        assert_eq!(bridge.frame_count, 2);
    }

    #[test]
    fn present_resolution() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        bridge.set_resolution(2560, 1440);
        assert_eq!(bridge.width, 2560);
        assert_eq!(bridge.height, 1440);
    }

    #[test]
    fn present_fullscreen() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        assert!(!bridge.fullscreen);
        bridge.set_fullscreen(true);
        assert!(bridge.fullscreen);
    }
}
