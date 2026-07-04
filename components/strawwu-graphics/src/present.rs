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

const MIN_WIDTH: u32 = 320;
const MIN_HEIGHT: u32 = 240;
const MAX_WIDTH: u32 = 7680;
const MAX_HEIGHT: u32 = 4320;

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

    pub fn frame_time_ms(&self) -> f64 {
        match self.vsync {
            VsyncMode::On => 1000.0 / 60.0,
            VsyncMode::Off => 0.0,
            VsyncMode::Adaptive => 1000.0 / 60.0,
        }
    }

    pub fn set_vsync(&mut self, mode: VsyncMode) {
        self.vsync = mode;
    }

    pub fn resize(&mut self, width: u32, height: u32) -> Result<(), PresentError> {
        if width < MIN_WIDTH || height < MIN_HEIGHT {
            return Err(PresentError::InvalidResolution);
        }
        if width > MAX_WIDTH || height > MAX_HEIGHT {
            return Err(PresentError::InvalidResolution);
        }
        self.width = width;
        self.height = height;
        Ok(())
    }

    pub fn target_fps(&self) -> u32 {
        match self.vsync {
            VsyncMode::On => 60,
            VsyncMode::Off => 0,
            VsyncMode::Adaptive => 60,
        }
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum PresentError {
    #[error("display surface lost")]
    SurfaceLost,
    #[error("present failed")]
    PresentFailed,
    #[error("invalid resolution")]
    InvalidResolution,
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

    #[test]
    fn present_frame_time_vsync_on() {
        let bridge = PresentBridge::new(DisplayBackend::Wayland);
        let ft = bridge.frame_time_ms();
        assert!((ft - 16.6666).abs() < 0.1);
    }

    #[test]
    fn present_frame_time_vsync_off() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        bridge.set_vsync(VsyncMode::Off);
        assert_eq!(bridge.frame_time_ms(), 0.0);
    }

    #[test]
    fn present_target_fps() {
        let mut bridge = PresentBridge::new(DisplayBackend::X11);
        assert_eq!(bridge.target_fps(), 60);
        bridge.set_vsync(VsyncMode::Off);
        assert_eq!(bridge.target_fps(), 0);
        bridge.set_vsync(VsyncMode::Adaptive);
        assert_eq!(bridge.target_fps(), 60);
    }

    #[test]
    fn present_resize_valid() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        bridge.resize(2560, 1440).unwrap();
        assert_eq!(bridge.width, 2560);
        assert_eq!(bridge.height, 1440);
    }

    #[test]
    fn present_resize_too_small() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        assert!(bridge.resize(100, 100).is_err());
        assert_eq!(bridge.width, 1920);
    }

    #[test]
    fn present_resize_too_large() {
        let mut bridge = PresentBridge::new(DisplayBackend::Wayland);
        assert!(bridge.resize(10000, 10000).is_err());
        assert_eq!(bridge.width, 1920);
    }
}
