use serde::{Deserialize, Serialize};

use std::collections::{HashMap, VecDeque};

use crate::ntdll::NtStatus;

// --- Window Handle (HWND) System ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub struct Hwnd(pub u64);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowClass {
    pub class_name: String,
    pub style: u32,
    pub instance: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Window {
    pub hwnd: Hwnd,
    pub class_name: String,
    pub title: String,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub visible: bool,
    pub parent: Option<Hwnd>,
    pub style: u32,
    pub ex_style: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WinMsg {
    pub hwnd: Hwnd,
    pub message: u32,
    pub wparam: u64,
    pub lparam: i64,
}

pub const WM_CREATE: u32 = 0x0001;
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_PAINT: u32 = 0x000F;
pub const WM_CLOSE: u32 = 0x0010;
pub const WM_QUIT: u32 = 0x0012;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;

#[derive(Debug, Default)]
pub struct WindowManager {
    classes: HashMap<String, WindowClass>,
    windows: HashMap<u64, Window>,
    message_queue: VecDeque<WinMsg>,
    next_hwnd: u64,
    desktop_hwnd: Hwnd,
}

impl WindowManager {
    pub fn new() -> Self {
        Self {
            classes: HashMap::new(),
            windows: HashMap::new(),
            message_queue: VecDeque::new(),
            next_hwnd: 0x0001_0000,
            desktop_hwnd: Hwnd(0x0000_FFFF),
        }
    }

    pub fn register_class(&mut self, class_name: &str, style: u32, instance: u64) -> bool {
        if self.classes.contains_key(class_name) {
            return false;
        }
        self.classes.insert(class_name.to_string(), WindowClass {
            class_name: class_name.to_string(),
            style,
            instance,
        });
        true
    }

    pub fn create_window(
        &mut self,
        class_name: &str,
        title: &str,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        parent: Option<Hwnd>,
        style: u32,
        ex_style: u32,
    ) -> Option<Hwnd> {
        if !self.classes.contains_key(class_name) {
            return None;
        }

        let hwnd = Hwnd(self.next_hwnd);
        self.next_hwnd += 1;

        let window = Window {
            hwnd,
            class_name: class_name.to_string(),
            title: title.to_string(),
            x,
            y,
            width,
            height,
            visible: false,
            parent,
            style,
            ex_style,
        };

        self.windows.insert(hwnd.0, window);

        self.message_queue.push_back(WinMsg {
            hwnd,
            message: WM_CREATE,
            wparam: 0,
            lparam: 0,
        });

        Some(hwnd)
    }

    pub fn show_window(&mut self, hwnd: Hwnd, show: bool) -> bool {
        if let Some(win) = self.windows.get_mut(&hwnd.0) {
            win.visible = show;
            if show {
                self.message_queue.push_back(WinMsg {
                    hwnd,
                    message: WM_PAINT,
                    wparam: 0,
                    lparam: 0,
                });
            }
            true
        } else {
            false
        }
    }

    pub fn destroy_window(&mut self, hwnd: Hwnd) -> bool {
        if self.windows.remove(&hwnd.0).is_some() {
            self.message_queue.push_back(WinMsg {
                hwnd,
                message: WM_DESTROY,
                wparam: 0,
                lparam: 0,
            });
            true
        } else {
            false
        }
    }

    pub fn get_message(&mut self) -> Option<WinMsg> {
        self.message_queue.pop_front()
    }

    pub fn post_message(&mut self, hwnd: Hwnd, message: u32, wparam: u64, lparam: i64) -> bool {
        if hwnd.0 != 0 && !self.windows.contains_key(&hwnd.0) {
            return false;
        }
        self.message_queue.push_back(WinMsg { hwnd, message, wparam, lparam });
        true
    }

    pub fn post_quit_message(&mut self, exit_code: i32) {
        self.message_queue.push_back(WinMsg {
            hwnd: Hwnd(0),
            message: WM_QUIT,
            wparam: exit_code as u64,
            lparam: 0,
        });
    }

    pub fn get_desktop_window(&self) -> Hwnd {
        self.desktop_hwnd
    }

    pub fn set_window_text(&mut self, hwnd: Hwnd, text: &str) -> bool {
        if let Some(win) = self.windows.get_mut(&hwnd.0) {
            win.title = text.to_string();
            true
        } else {
            false
        }
    }

    pub fn get_window(&self, hwnd: Hwnd) -> Option<&Window> {
        self.windows.get(&hwnd.0)
    }

    pub fn window_count(&self) -> usize {
        self.windows.len()
    }

    pub fn pending_messages(&self) -> usize {
        self.message_queue.len()
    }
}

// --- GDI Device Context ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Hdc(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct HGdiObj(pub u64);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceContext {
    pub hdc: Hdc,
    pub width: u32,
    pub height: u32,
    pub bits_per_pixel: u32,
    pub selected_objects: Vec<HGdiObj>,
    pub background_mode: u32,
    pub text_color: u32,
    pub bk_color: u32,
}

#[derive(Debug, Default)]
pub struct GdiManager {
    contexts: HashMap<u64, DeviceContext>,
    next_hdc: u64,
    next_obj: u64,
}

impl GdiManager {
    pub fn new() -> Self {
        Self {
            contexts: HashMap::new(),
            next_hdc: 0xDC_0001,
            next_obj: 0xAB_0001,
        }
    }

    pub fn create_dc(&mut self, width: u32, height: u32) -> Hdc {
        let hdc = Hdc(self.next_hdc);
        self.next_hdc += 1;
        self.contexts.insert(hdc.0, DeviceContext {
            hdc,
            width,
            height,
            bits_per_pixel: 32,
            selected_objects: Vec::new(),
            background_mode: 1, // TRANSPARENT
            text_color: 0x0000_0000,
            bk_color: 0x00FF_FFFF,
        });
        hdc
    }

    pub fn create_compatible_dc(&mut self, source: Hdc) -> Option<Hdc> {
        let src = self.contexts.get(&source.0)?;
        let width = src.width;
        let height = src.height;
        Some(self.create_dc(width, height))
    }

    pub fn delete_dc(&mut self, hdc: Hdc) -> bool {
        self.contexts.remove(&hdc.0).is_some()
    }

    pub fn select_object(&mut self, hdc: Hdc, obj: HGdiObj) -> Option<HGdiObj> {
        let dc = self.contexts.get_mut(&hdc.0)?;
        let old = dc.selected_objects.last().copied();
        dc.selected_objects.push(obj);
        old
    }

    pub fn get_device_caps(&self, hdc: Hdc, cap_index: u32) -> Option<u32> {
        let dc = self.contexts.get(&hdc.0)?;
        match cap_index {
            8 => Some(dc.width),    // HORZRES
            10 => Some(dc.height),  // VERTRES
            12 => Some(dc.bits_per_pixel), // BITSPIXEL
            88 => Some(96),         // LOGPIXELSX
            90 => Some(96),         // LOGPIXELSY
            _ => Some(0),
        }
    }

    pub fn set_bk_mode(&mut self, hdc: Hdc, mode: u32) -> Option<u32> {
        let dc = self.contexts.get_mut(&hdc.0)?;
        let old = dc.background_mode;
        dc.background_mode = mode;
        Some(old)
    }

    pub fn create_gdi_object(&mut self) -> HGdiObj {
        let obj = HGdiObj(self.next_obj);
        self.next_obj += 1;
        obj
    }

    pub fn dc_count(&self) -> usize {
        self.contexts.len()
    }
}

// --- Original Win32 DLL and Stub types below ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Win32Dll {
    Kernel32,
    User32,
    Gdi32,
    Advapi32,
    Shell32,
    Ole32,
    Oleaut32,
    Comctl32,
    Msvcrt,
    Ntdll,
    Ws2_32,
}

impl Win32Dll {
    pub fn name(&self) -> &'static str {
        match self {
            Self::Kernel32 => "kernel32.dll",
            Self::User32 => "user32.dll",
            Self::Gdi32 => "gdi32.dll",
            Self::Advapi32 => "advapi32.dll",
            Self::Shell32 => "shell32.dll",
            Self::Ole32 => "ole32.dll",
            Self::Oleaut32 => "oleaut32.dll",
            Self::Comctl32 => "comctl32.dll",
            Self::Msvcrt => "msvcrt.dll",
            Self::Ntdll => "ntdll.dll",
            Self::Ws2_32 => "ws2_32.dll",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        let lower = name.to_lowercase();
        match lower.as_str() {
            "kernel32.dll" | "kernel32" => Some(Self::Kernel32),
            "user32.dll" | "user32" => Some(Self::User32),
            "gdi32.dll" | "gdi32" => Some(Self::Gdi32),
            "advapi32.dll" | "advapi32" => Some(Self::Advapi32),
            "shell32.dll" | "shell32" => Some(Self::Shell32),
            "ole32.dll" | "ole32" => Some(Self::Ole32),
            "oleaut32.dll" | "oleaut32" => Some(Self::Oleaut32),
            "comctl32.dll" | "comctl32" => Some(Self::Comctl32),
            "msvcrt.dll" | "msvcrt" => Some(Self::Msvcrt),
            "ntdll.dll" | "ntdll" => Some(Self::Ntdll),
            "ws2_32.dll" | "ws2_32" => Some(Self::Ws2_32),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StubStatus {
    Implemented,
    Stub,
    NotImplemented,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Win32Function {
    pub dll: String,
    pub name: String,
    pub status: StubStatus,
}

#[derive(Debug)]
pub struct Win32StubRegistry {
    stubs: Vec<Win32Function>,
}

impl Win32StubRegistry {
    pub fn new() -> Self {
        let mut reg = Self { stubs: Vec::new() };
        reg.register_kernel32_stubs();
        reg.register_user32_stubs();
        reg.register_gdi32_stubs();
        reg.register_com_stubs();
        reg
    }

    fn register_kernel32_stubs(&mut self) {
        let funcs = [
            ("GetModuleHandleA", StubStatus::Stub),
            ("GetModuleHandleW", StubStatus::Stub),
            ("GetProcAddress", StubStatus::Stub),
            ("LoadLibraryA", StubStatus::Stub),
            ("LoadLibraryW", StubStatus::Stub),
            ("GetLastError", StubStatus::Implemented),
            ("SetLastError", StubStatus::Implemented),
            ("GetStdHandle", StubStatus::Implemented),
            ("GetCurrentProcessId", StubStatus::Implemented),
            ("GetCurrentThreadId", StubStatus::Implemented),
            ("GetCommandLineA", StubStatus::Implemented),
            ("GetCommandLineW", StubStatus::Stub),
            ("GetSystemInfo", StubStatus::Stub),
            ("VirtualAlloc", StubStatus::Stub),
            ("VirtualFree", StubStatus::Stub),
            ("CreateFileA", StubStatus::Implemented),
            ("CreateFileW", StubStatus::Stub),
            ("ReadFile", StubStatus::Implemented),
            ("WriteFile", StubStatus::Implemented),
            ("CloseHandle", StubStatus::Implemented),
            ("GetVersionExA", StubStatus::Stub),
            ("GetVersionExW", StubStatus::Stub),
            ("ExitProcess", StubStatus::Implemented),
            ("CreateProcessA", StubStatus::Stub),
            ("CreateProcessW", StubStatus::Stub),
            ("GetProcessHeap", StubStatus::Implemented),
            ("HeapCreate", StubStatus::Stub),
            ("HeapAlloc", StubStatus::Implemented),
            ("HeapFree", StubStatus::Implemented),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "kernel32.dll".into(),
                name: name.into(),
                status,
            });
        }
        self.register_msvcrt_stubs();
    }

    fn register_msvcrt_stubs(&mut self) {
        let funcs = [
            ("malloc", StubStatus::Implemented),
            ("free", StubStatus::Implemented),
            ("puts", StubStatus::Implemented),
            ("printf", StubStatus::Stub),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "msvcrt.dll".into(),
                name: name.into(),
                status,
            });
        }
    }

    fn register_user32_stubs(&mut self) {
        let funcs = [
            ("RegisterClassA", StubStatus::Implemented),
            ("RegisterClassExW", StubStatus::Stub),
            ("CreateWindowExA", StubStatus::Implemented),
            ("CreateWindowExW", StubStatus::Stub),
            ("ShowWindow", StubStatus::Implemented),
            ("UpdateWindow", StubStatus::Implemented),
            ("GetMessageA", StubStatus::Implemented),
            ("GetMessageW", StubStatus::Stub),
            ("TranslateMessage", StubStatus::Implemented),
            ("DispatchMessageA", StubStatus::Implemented),
            ("DispatchMessageW", StubStatus::Stub),
            ("DestroyWindow", StubStatus::Implemented),
            ("PostQuitMessage", StubStatus::Implemented),
            ("DefWindowProcW", StubStatus::Stub),
            ("GetDC", StubStatus::Implemented),
            ("ReleaseDC", StubStatus::Implemented),
            ("MessageBoxA", StubStatus::Stub),
            ("MessageBoxW", StubStatus::Stub),
            ("SendMessageW", StubStatus::Stub),
            ("PostMessageW", StubStatus::Stub),
            ("GetDesktopWindow", StubStatus::Stub),
            ("SetWindowTextW", StubStatus::Stub),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "user32.dll".into(),
                name: name.into(),
                status,
            });
        }
    }

    fn register_gdi32_stubs(&mut self) {
        let funcs = [
            ("CreateDCA", StubStatus::Stub),
            ("CreateDCW", StubStatus::Stub),
            ("GetDeviceCaps", StubStatus::Implemented),
            ("SelectObject", StubStatus::Stub),
            ("DeleteObject", StubStatus::Stub),
            ("BitBlt", StubStatus::Implemented),
            ("CreateCompatibleDC", StubStatus::Implemented),
            ("DeleteDC", StubStatus::Implemented),
            ("CreateCompatibleBitmap", StubStatus::Stub),
            ("TextOutW", StubStatus::Stub),
            ("SetBkMode", StubStatus::Stub),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "gdi32.dll".into(),
                name: name.into(),
                status,
            });
        }
    }

    fn register_com_stubs(&mut self) {
        let funcs = [
            ("CoInitializeEx", StubStatus::Stub),
            ("CoUninitialize", StubStatus::Stub),
            ("CoCreateInstance", StubStatus::Stub),
            ("CLSIDFromProgID", StubStatus::NotImplemented),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "ole32.dll".into(),
                name: name.into(),
                status,
            });
        }
    }

    pub fn lookup(&self, dll: &str, func: &str) -> Option<&Win32Function> {
        let dll_lower = dll.to_lowercase();
        self.stubs.iter().find(|f| {
            f.dll.to_lowercase() == dll_lower && f.name == func
        })
    }

    pub fn resolve(&self, dll: &str, func: &str) -> NtStatus {
        match self.lookup(dll, func) {
            Some(f) => match f.status {
                StubStatus::Implemented => NtStatus::Success,
                StubStatus::Stub => NtStatus::Success,
                StubStatus::NotImplemented => NtStatus::NotImplemented,
            },
            None => NtStatus::ObjectNameNotFound,
        }
    }

    pub fn total_count(&self) -> usize {
        self.stubs.len()
    }

    pub fn implemented_count(&self) -> usize {
        self.stubs.iter().filter(|f| f.status == StubStatus::Implemented).count()
    }

    pub fn stub_count(&self) -> usize {
        self.stubs.iter().filter(|f| f.status == StubStatus::Stub).count()
    }

    pub fn all_functions(&self) -> &[Win32Function] {
        &self.stubs
    }
}

impl Default for Win32StubRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dll_name_lookup() {
        assert_eq!(Win32Dll::from_name("kernel32.dll"), Some(Win32Dll::Kernel32));
        assert_eq!(Win32Dll::from_name("USER32.DLL"), Some(Win32Dll::User32));
        assert_eq!(Win32Dll::from_name("nonexistent.dll"), None);
    }

    #[test]
    fn stub_registry_creation() {
        let reg = Win32StubRegistry::new();
        assert!(reg.total_count() > 0);
        assert!(reg.implemented_count() > 0);
        assert!(reg.stub_count() > 0);
    }

    #[test]
    fn stub_resolve_implemented() {
        let reg = Win32StubRegistry::new();
        assert_eq!(reg.resolve("kernel32.dll", "GetLastError"), NtStatus::Success);
        assert_eq!(reg.resolve("kernel32.dll", "CloseHandle"), NtStatus::Success);
    }

    #[test]
    fn stub_resolve_stub() {
        let reg = Win32StubRegistry::new();
        assert_eq!(reg.resolve("user32.dll", "CreateWindowExW"), NtStatus::Success);
    }

    #[test]
    fn stub_resolve_not_implemented() {
        let reg = Win32StubRegistry::new();
        assert_eq!(reg.resolve("ole32.dll", "CLSIDFromProgID"), NtStatus::NotImplemented);
    }

    #[test]
    fn stub_resolve_unknown_function() {
        let reg = Win32StubRegistry::new();
        assert_eq!(reg.resolve("kernel32.dll", "NonexistentFunc"), NtStatus::ObjectNameNotFound);
    }

    #[test]
    fn user32_stubs_present() {
        let reg = Win32StubRegistry::new();
        assert!(reg.lookup("user32.dll", "CreateWindowExW").is_some());
        assert!(reg.lookup("user32.dll", "MessageBoxW").is_some());
    }

    #[test]
    fn gdi32_stubs_present() {
        let reg = Win32StubRegistry::new();
        assert!(reg.lookup("gdi32.dll", "BitBlt").is_some());
        assert!(reg.lookup("gdi32.dll", "CreateCompatibleDC").is_some());
    }

    // Window Manager tests

    #[test]
    fn window_create_and_show() {
        let mut wm = WindowManager::new();
        wm.register_class("MyWndClass", 0, 0x1000);
        let hwnd = wm.create_window("MyWndClass", "Hello", 100, 100, 800, 600, None, 0, 0).unwrap();
        assert!(hwnd.0 > 0);
        assert_eq!(wm.window_count(), 1);

        wm.show_window(hwnd, true);
        let win = wm.get_window(hwnd).unwrap();
        assert!(win.visible);
        assert_eq!(win.title, "Hello");
    }

    #[test]
    fn window_unregistered_class_fails() {
        let mut wm = WindowManager::new();
        assert!(wm.create_window("NoClass", "X", 0, 0, 100, 100, None, 0, 0).is_none());
    }

    #[test]
    fn window_message_queue() {
        let mut wm = WindowManager::new();
        wm.register_class("Cls", 0, 0);
        let hwnd = wm.create_window("Cls", "T", 0, 0, 640, 480, None, 0, 0).unwrap();

        // WM_CREATE should be queued
        let msg = wm.get_message().unwrap();
        assert_eq!(msg.message, WM_CREATE);
        assert_eq!(msg.hwnd, hwnd);

        wm.post_message(hwnd, WM_KEYDOWN, 0x41, 0);
        let msg2 = wm.get_message().unwrap();
        assert_eq!(msg2.message, WM_KEYDOWN);
    }

    #[test]
    fn window_quit_message() {
        let mut wm = WindowManager::new();
        wm.post_quit_message(0);
        let msg = wm.get_message().unwrap();
        assert_eq!(msg.message, WM_QUIT);
    }

    #[test]
    fn window_destroy() {
        let mut wm = WindowManager::new();
        wm.register_class("C", 0, 0);
        let hwnd = wm.create_window("C", "X", 0, 0, 100, 100, None, 0, 0).unwrap();
        wm.get_message(); // drain WM_CREATE
        assert!(wm.destroy_window(hwnd));
        assert_eq!(wm.window_count(), 0);
        let msg = wm.get_message().unwrap();
        assert_eq!(msg.message, WM_DESTROY);
    }

    #[test]
    fn window_set_text() {
        let mut wm = WindowManager::new();
        wm.register_class("C", 0, 0);
        let hwnd = wm.create_window("C", "Old", 0, 0, 100, 100, None, 0, 0).unwrap();
        wm.set_window_text(hwnd, "New Title");
        assert_eq!(wm.get_window(hwnd).unwrap().title, "New Title");
    }

    #[test]
    fn window_desktop() {
        let wm = WindowManager::new();
        let desktop = wm.get_desktop_window();
        assert!(desktop.0 > 0);
    }

    // GDI Manager tests

    #[test]
    fn gdi_create_dc() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(1920, 1080);
        assert!(hdc.0 > 0);
        assert_eq!(gdi.dc_count(), 1);
    }

    #[test]
    fn gdi_compatible_dc() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(800, 600);
        let compat = gdi.create_compatible_dc(hdc).unwrap();
        assert_ne!(hdc.0, compat.0);
        assert_eq!(gdi.dc_count(), 2);
    }

    #[test]
    fn gdi_device_caps() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(1920, 1080);
        assert_eq!(gdi.get_device_caps(hdc, 8), Some(1920));  // HORZRES
        assert_eq!(gdi.get_device_caps(hdc, 10), Some(1080)); // VERTRES
        assert_eq!(gdi.get_device_caps(hdc, 12), Some(32));   // BITSPIXEL
        assert_eq!(gdi.get_device_caps(hdc, 88), Some(96));   // LOGPIXELSX
    }

    #[test]
    fn gdi_select_object() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(100, 100);
        let obj = gdi.create_gdi_object();
        gdi.select_object(hdc, obj);
    }

    #[test]
    fn gdi_delete_dc() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(100, 100);
        assert!(gdi.delete_dc(hdc));
        assert_eq!(gdi.dc_count(), 0);
    }

    #[test]
    fn gdi_set_bk_mode() {
        let mut gdi = GdiManager::new();
        let hdc = gdi.create_dc(100, 100);
        let old = gdi.set_bk_mode(hdc, 2).unwrap(); // OPAQUE
        assert_eq!(old, 1); // was TRANSPARENT
    }
}
