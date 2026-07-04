use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessEnvironmentBlock {
    pub image_base: u64,
    pub process_id: u64,
    pub session_id: String,
    pub being_debugged: bool,
    pub command_line: String,
    pub environment: Vec<(String, String)>,
    pub current_directory: String,
    pub module_list: Vec<LoadedModule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadedModule {
    pub name: String,
    pub base_address: u64,
    pub size: u64,
    pub entry_point: u64,
}

impl ProcessEnvironmentBlock {
    pub fn new(pid: u64, session_id: &str, image_base: u64) -> Self {
        Self {
            image_base,
            process_id: pid,
            session_id: session_id.to_string(),
            being_debugged: false,
            command_line: String::new(),
            environment: vec![
                ("SystemRoot".into(), "C:\\Windows".into()),
                ("SystemDrive".into(), "C:".into()),
                ("TEMP".into(), "C:\\Users\\user\\AppData\\Local\\Temp".into()),
                ("TMP".into(), "C:\\Users\\user\\AppData\\Local\\Temp".into()),
            ],
            current_directory: "C:\\".into(),
            module_list: Vec::new(),
        }
    }

    pub fn add_module(&mut self, module: LoadedModule) {
        self.module_list.push(module);
    }

    pub fn find_module(&self, name: &str) -> Option<&LoadedModule> {
        let name_lower = name.to_lowercase();
        self.module_list.iter().find(|m| m.name.to_lowercase() == name_lower)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThreadEnvironmentBlock {
    pub thread_id: u64,
    pub process_id: u64,
    pub stack_base: u64,
    pub stack_limit: u64,
    pub tls_slots: Vec<u64>,
    pub last_error: u32,
    pub locale_id: u32,
}

impl ThreadEnvironmentBlock {
    pub fn new(thread_id: u64, process_id: u64) -> Self {
        Self {
            thread_id,
            process_id,
            stack_base: 0x0000_0080_0000_0000,
            stack_limit: 0x0000_0080_0000_0000 - (1024 * 1024),
            tls_slots: vec![0; 64],
            last_error: 0,
            locale_id: 0x0409, // en-US
        }
    }

    pub fn set_last_error(&mut self, code: u32) {
        self.last_error = code;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn peb_creation() {
        let peb = ProcessEnvironmentBlock::new(100, "sess-01", 0x14000_0000);
        assert_eq!(peb.process_id, 100);
        assert_eq!(peb.session_id, "sess-01");
        assert!(!peb.being_debugged);
        assert!(!peb.environment.is_empty());
    }

    #[test]
    fn peb_module_list() {
        let mut peb = ProcessEnvironmentBlock::new(100, "s", 0x14000_0000);
        peb.add_module(LoadedModule {
            name: "ntdll.dll".into(),
            base_address: 0x7FFE_0000,
            size: 0x1000,
            entry_point: 0,
        });
        peb.add_module(LoadedModule {
            name: "kernel32.dll".into(),
            base_address: 0x7FF0_0000,
            size: 0x2000,
            entry_point: 0x7FF0_1000,
        });
        assert_eq!(peb.module_list.len(), 2);
        assert!(peb.find_module("NTDLL.DLL").is_some());
        assert!(peb.find_module("missing.dll").is_none());
    }

    #[test]
    fn teb_creation() {
        let teb = ThreadEnvironmentBlock::new(1, 100);
        assert_eq!(teb.thread_id, 1);
        assert_eq!(teb.process_id, 100);
        assert_eq!(teb.last_error, 0);
        assert_eq!(teb.tls_slots.len(), 64);
    }

    #[test]
    fn teb_set_last_error() {
        let mut teb = ThreadEnvironmentBlock::new(1, 100);
        teb.set_last_error(0x05); // ERROR_ACCESS_DENIED
        assert_eq!(teb.last_error, 0x05);
    }
}
