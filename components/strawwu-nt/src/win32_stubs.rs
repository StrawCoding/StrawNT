use serde::{Deserialize, Serialize};

use crate::ntdll::NtStatus;

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
            ("GetCurrentProcessId", StubStatus::Implemented),
            ("GetCurrentThreadId", StubStatus::Implemented),
            ("GetSystemInfo", StubStatus::Stub),
            ("VirtualAlloc", StubStatus::Stub),
            ("VirtualFree", StubStatus::Stub),
            ("CreateFileA", StubStatus::Stub),
            ("CreateFileW", StubStatus::Stub),
            ("ReadFile", StubStatus::Stub),
            ("WriteFile", StubStatus::Stub),
            ("CloseHandle", StubStatus::Implemented),
            ("GetVersionExA", StubStatus::Stub),
            ("GetVersionExW", StubStatus::Stub),
            ("ExitProcess", StubStatus::Implemented),
            ("CreateProcessA", StubStatus::Stub),
            ("CreateProcessW", StubStatus::Stub),
            ("HeapCreate", StubStatus::Stub),
            ("HeapAlloc", StubStatus::Stub),
            ("HeapFree", StubStatus::Stub),
        ];
        for (name, status) in funcs {
            self.stubs.push(Win32Function {
                dll: "kernel32.dll".into(),
                name: name.into(),
                status,
            });
        }
    }

    fn register_user32_stubs(&mut self) {
        let funcs = [
            ("RegisterClassExW", StubStatus::Stub),
            ("CreateWindowExW", StubStatus::Stub),
            ("ShowWindow", StubStatus::Stub),
            ("UpdateWindow", StubStatus::Stub),
            ("GetMessageW", StubStatus::Stub),
            ("TranslateMessage", StubStatus::Stub),
            ("DispatchMessageW", StubStatus::Stub),
            ("PostQuitMessage", StubStatus::Stub),
            ("DefWindowProcW", StubStatus::Stub),
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
            ("GetDeviceCaps", StubStatus::Stub),
            ("SelectObject", StubStatus::Stub),
            ("DeleteObject", StubStatus::Stub),
            ("BitBlt", StubStatus::Stub),
            ("CreateCompatibleDC", StubStatus::Stub),
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
}
