use serde::{Deserialize, Serialize};

use crate::pe::{PeFile, PeMachine};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Wow64Mode {
    Disabled,
    Active,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Wow64Context {
    pub mode: Wow64Mode,
    pub host_machine: PeMachine,
    pub guest_machine: PeMachine,
    pub syswow64_path: String,
    pub redirected_paths: Vec<(String, String)>,
}

impl Wow64Context {
    pub fn for_pe(pe: &PeFile) -> Self {
        if pe.needs_wow64() {
            Self {
                mode: Wow64Mode::Active,
                host_machine: PeMachine::Amd64,
                guest_machine: pe.machine,
                syswow64_path: r"C:\Windows\SysWOW64".to_string(),
                redirected_paths: vec![
                    (r"C:\Windows\System32".into(), r"C:\Windows\SysWOW64".into()),
                    (r"C:\Program Files".into(), r"C:\Program Files (x86)".into()),
                ],
            }
        } else {
            Self::disabled()
        }
    }

    pub fn disabled() -> Self {
        Self {
            mode: Wow64Mode::Disabled,
            host_machine: PeMachine::Amd64,
            guest_machine: PeMachine::Amd64,
            syswow64_path: String::new(),
            redirected_paths: Vec::new(),
        }
    }

    pub fn is_active(&self) -> bool {
        self.mode == Wow64Mode::Active
    }

    pub fn redirect_path(&self, path: &str) -> String {
        if !self.is_active() {
            return path.to_string();
        }
        for (from, to) in &self.redirected_paths {
            if path.to_lowercase().starts_with(&from.to_lowercase()) {
                return format!("{}{}", to, &path[from.len()..]);
            }
        }
        path.to_string()
    }

    pub fn is_wow64_process(&self) -> bool {
        self.is_active() && self.guest_machine.is_32bit()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pe::{build_stub_pe, PeSubsystem};

    #[test]
    fn wow64_for_32bit_pe() {
        let data = build_stub_pe(PeMachine::I386, PeSubsystem::WindowsGui);
        let pe = PeFile::parse(&data).unwrap();
        let ctx = Wow64Context::for_pe(&pe);
        assert!(ctx.is_active());
        assert!(ctx.is_wow64_process());
        assert_eq!(ctx.guest_machine, PeMachine::I386);
    }

    #[test]
    fn wow64_disabled_for_64bit() {
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let pe = PeFile::parse(&data).unwrap();
        let ctx = Wow64Context::for_pe(&pe);
        assert!(!ctx.is_active());
        assert!(!ctx.is_wow64_process());
    }

    #[test]
    fn wow64_path_redirect() {
        let data = build_stub_pe(PeMachine::I386, PeSubsystem::WindowsCui);
        let pe = PeFile::parse(&data).unwrap();
        let ctx = Wow64Context::for_pe(&pe);

        let redirected = ctx.redirect_path(r"C:\Windows\System32\kernel32.dll");
        assert_eq!(redirected, r"C:\Windows\SysWOW64\kernel32.dll");

        let pf = ctx.redirect_path(r"C:\Program Files\App\test.exe");
        assert_eq!(pf, r"C:\Program Files (x86)\App\test.exe");
    }

    #[test]
    fn wow64_no_redirect_when_disabled() {
        let ctx = Wow64Context::disabled();
        let path = r"C:\Windows\System32\ntdll.dll";
        assert_eq!(ctx.redirect_path(path), path);
    }
}
