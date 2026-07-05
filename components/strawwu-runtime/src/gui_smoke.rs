use serde::{Deserialize, Serialize};

use strawwu_graphics::present::{DisplayBackend, PresentBridge};
use strawwu_nt::pe::{PeFile, PeSubsystem};
use strawwu_nt::win32_stubs::WindowManager;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GuiSmokeState {
    Skipped,
    WindowCreated,
    Presented,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GuiSmokeResult {
    pub app_id: String,
    pub title: String,
    pub hwnd: u64,
    pub width: u32,
    pub height: u32,
    pub visible: bool,
    pub display_backend: String,
    pub compositor: String,
    pub frame_count: u64,
    pub state: GuiSmokeState,
}

pub fn pe_subsystem(data: &[u8]) -> Option<PeSubsystem> {
    PeFile::parse(data).ok().map(|pe| pe.subsystem)
}

pub fn is_gui_pe(data: &[u8]) -> bool {
    matches!(pe_subsystem(data), Some(PeSubsystem::WindowsGui))
}

fn resolve_display_backend() -> DisplayBackend {
    match std::env::var("STRAWWU_DISPLAY_BACKEND")
        .unwrap_or_else(|_| "wayland".into())
        .to_ascii_lowercase()
        .as_str()
    {
        "x11" => DisplayBackend::X11,
        _ => DisplayBackend::Wayland,
    }
}

fn compositor_for_backend(backend: DisplayBackend) -> &'static str {
    match backend {
        DisplayBackend::Wayland => "mutter",
        DisplayBackend::X11 => "mutter-x11",
    }
}

/// Simulate GUI app window creation + present bridge (W5-W4 smoke).
/// Real Mutter integration is future work; this expands Win32 HWND → compositor contract.
pub fn run_gui_smoke(app_id: &str, title: &str, width: u32, height: u32) -> Result<GuiSmokeResult, String> {
    let display_backend = resolve_display_backend();
    let mut wm = WindowManager::new();
    wm.register_class("StrawWUGuiSmokeWnd", 0, 0);

    let hwnd = wm
        .create_window("StrawWUGuiSmokeWnd", title, 100, 100, width, height, None, 0, 0)
        .ok_or_else(|| "CreateWindowExW failed".to_string())?;

    wm.show_window(hwnd, true);
    if !wm.get_window(hwnd).map(|w| w.visible).unwrap_or(false) {
        return Err("ShowWindow did not mark window visible".into());
    }

    let mut present = PresentBridge::new(display_backend);
    present
        .resize(width, height)
        .map_err(|e| e.to_string())?;
    present.present_frame().map_err(|e| e.to_string())?;

    Ok(GuiSmokeResult {
        app_id: app_id.to_string(),
        title: title.to_string(),
        hwnd: hwnd.0,
        width: present.width,
        height: present.height,
        visible: true,
        display_backend: format!("{:?}", display_backend).to_ascii_lowercase(),
        compositor: compositor_for_backend(display_backend).to_string(),
        frame_count: present.frame_count,
        state: GuiSmokeState::Presented,
    })
}

pub fn maybe_run_gui_smoke(
    pe_data: &[u8],
    app_id: &str,
    title: &str,
) -> Result<Option<GuiSmokeResult>, String> {
    if !is_gui_pe(pe_data) {
        return Ok(None);
    }
    let width = 640;
    let height = 480;
    Ok(Some(run_gui_smoke(app_id, title, width, height)?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use strawwu_nt::pe::{build_stub_pe, PeMachine};

    #[test]
    fn gui_pe_detected() {
        let pe = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        assert!(is_gui_pe(&pe));
    }

    #[test]
    fn cui_pe_skipped() {
        let pe = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsCui);
        assert!(!is_gui_pe(&pe));
    }

    #[test]
    fn gui_smoke_notepad() {
        let result = run_gui_smoke("notepad", "Notepad", 800, 600).unwrap();
        assert_eq!(result.app_id, "notepad");
        assert!(result.visible);
        assert!(result.hwnd > 0);
        assert_eq!(result.state, GuiSmokeState::Presented);
        assert_eq!(result.compositor, "mutter");
        assert!(result.frame_count >= 1);
    }

    #[test]
    fn maybe_smoke_from_stub_pe() {
        let pe = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let smoke = maybe_run_gui_smoke(&pe, "notepad", "Notepad").unwrap();
        assert!(smoke.is_some());
        assert_eq!(smoke.unwrap().app_id, "notepad");
    }
}
