use crate::ntdll::{MemoryProtection, NtKernel, NtStatus};
use crate::pe::PeFile;
use crate::teb::{LoadedModule, ProcessEnvironmentBlock, ThreadEnvironmentBlock};
use crate::win32_stubs::Win32StubRegistry;
use crate::wow64::Wow64Context;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoaderState {
    Idle,
    Parsing,
    Mapping,
    ResolvingImports,
    Ready,
    Running,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportResolution {
    pub dll_name: String,
    pub function_name: String,
    pub resolved_address: u64,
    pub resolved: bool,
}

#[derive(Debug)]
pub struct PeLoader {
    pub state: LoaderState,
    pub pe: Option<PeFile>,
    pub wow64: Option<Wow64Context>,
    pub mapped_base: u64,
    pub import_resolutions: Vec<ImportResolution>,
    pub entry_point_va: u64,
    stubs: Win32StubRegistry,
}

impl PeLoader {
    pub fn new() -> Self {
        Self {
            state: LoaderState::Idle,
            pe: None,
            wow64: None,
            mapped_base: 0,
            import_resolutions: Vec::new(),
            entry_point_va: 0,
            stubs: Win32StubRegistry::new(),
        }
    }

    pub fn load(&mut self, data: &[u8], kernel: &mut NtKernel) -> Result<LoadResult, NtStatus> {
        self.state = LoaderState::Parsing;

        let pe = PeFile::parse(data).map_err(|_| NtStatus::InvalidParameter)?;

        self.wow64 = Some(Wow64Context::for_pe(&pe));

        self.state = LoaderState::Mapping;

        // Widen to u64 before adding: virtual_address + size can exceed u32::MAX
        // for a crafted/large PE and must not wrap around.
        let total_size = pe
            .sections
            .iter()
            .map(|s| s.virtual_address as u64 + s.virtual_size.max(s.raw_size) as u64)
            .max()
            .unwrap_or(0x1000)
            .max(0x2000);

        let mapped_base = kernel
            .memory
            .allocate(total_size, MemoryProtection::ReadWriteExecute)?;
        self.mapped_base = mapped_base;

        // Copy raw section bytes into the guest image (real exec requires this).
        for section in &pe.sections {
            let dst = mapped_base + section.virtual_address as u64;
            let src_off = section.raw_offset as usize;
            let raw_size = section.raw_size as usize;
            if raw_size == 0 {
                continue;
            }
            if src_off.saturating_add(raw_size) > data.len() {
                continue;
            }
            let chunk = &data[src_off..src_off + raw_size];
            kernel
                .memory
                .write_bytes(dst, chunk)
                .map_err(|_| NtStatus::InvalidParameter)?;
        }

        self.state = LoaderState::ResolvingImports;

        let mut resolutions = Vec::new();
        // Fixed stub page shared with cpu.rs host callables.
        let mut stub_addr: u64 = crate::cpu::STUB_BASE;
        // Prefer known pe1 stubs at fixed slots when present.
        let fixed = [
            ("GetStdHandle", crate::cpu::STUB_GET_STD_HANDLE),
            ("WriteFile", crate::cpu::STUB_WRITE_FILE),
            ("ExitProcess", crate::cpu::STUB_EXIT_PROCESS),
            ("CreateFileA", crate::cpu::STUB_CREATE_FILE_A),
            ("CloseHandle", crate::cpu::STUB_CLOSE_HANDLE),
            ("ReadFile", crate::cpu::STUB_READ_FILE),
            ("GetCurrentProcessId", crate::cpu::STUB_GET_CURRENT_PROCESS_ID),
            ("GetCommandLineA", crate::cpu::STUB_GET_COMMAND_LINE_A),
            ("GetProcessHeap", crate::cpu::STUB_GET_PROCESS_HEAP),
            ("HeapAlloc", crate::cpu::STUB_HEAP_ALLOC),
            ("HeapFree", crate::cpu::STUB_HEAP_FREE),
            ("malloc", crate::cpu::STUB_MALLOC),
            ("free", crate::cpu::STUB_FREE),
            ("puts", crate::cpu::STUB_PUTS),
        ];

        for import in &pe.imports {
            for func_name in &import.functions {
                let resolve_status = self.stubs.resolve(&import.dll_name, func_name);
                let resolved = resolve_status == NtStatus::Success;
                let addr = fixed
                    .iter()
                    .find(|(n, _)| *n == func_name.as_str())
                    .map(|(_, a)| *a)
                    .unwrap_or_else(|| {
                        let a = stub_addr;
                        stub_addr += 8;
                        a
                    });
                resolutions.push(ImportResolution {
                    dll_name: import.dll_name.clone(),
                    function_name: func_name.clone(),
                    resolved_address: if resolved { addr } else { 0 },
                    resolved,
                });
            }
        }

        self.import_resolutions = resolutions.clone();
        self.entry_point_va = mapped_base + pe.entry_point as u64;
        self.pe = Some(pe);
        self.state = LoaderState::Ready;

        let unresolved: Vec<_> = resolutions.iter()
            .filter(|r| !r.resolved)
            .map(|r| format!("{}!{}", r.dll_name, r.function_name))
            .collect();

        Ok(LoadResult {
            mapped_base,
            entry_point_va: self.entry_point_va,
            total_imports: resolutions.len(),
            resolved_imports: resolutions.iter().filter(|r| r.resolved).count(),
            unresolved_imports: unresolved,
        })
    }

    pub fn build_peb(&self, pid: u64, session_id: &str) -> ProcessEnvironmentBlock {
        let pe = self.pe.as_ref().expect("PE must be loaded");
        let mut peb = ProcessEnvironmentBlock::new(pid, session_id, self.mapped_base);

        peb.add_module(LoadedModule {
            name: "ntdll.dll".into(),
            base_address: 0x7FFE_0000_0000,
            size: 0x1000,
            entry_point: 0,
        });
        peb.add_module(LoadedModule {
            name: "kernel32.dll".into(),
            base_address: 0x7FFE_0001_0000,
            size: 0x2000,
            entry_point: 0x7FFE_0001_1000,
        });

        for import in &pe.imports {
            if import.dll_name.to_lowercase() != "ntdll.dll"
                && import.dll_name.to_lowercase() != "kernel32.dll"
            {
                peb.add_module(LoadedModule {
                    name: import.dll_name.clone(),
                    base_address: 0x7FFE_0002_0000 + (peb.module_list.len() as u64 * 0x1_0000),
                    size: 0x1000,
                    entry_point: 0,
                });
            }
        }

        peb
    }

    pub fn build_teb(&self, thread_id: u64, process_id: u64) -> ThreadEnvironmentBlock {
        ThreadEnvironmentBlock::new(thread_id, process_id)
    }

    pub fn is_ready(&self) -> bool {
        self.state == LoaderState::Ready
    }

    pub fn resolution_rate(&self) -> f64 {
        if self.import_resolutions.is_empty() {
            return 1.0;
        }
        let resolved = self.import_resolutions.iter().filter(|r| r.resolved).count();
        resolved as f64 / self.import_resolutions.len() as f64
    }
}

impl Default for PeLoader {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadResult {
    pub mapped_base: u64,
    pub entry_point_va: u64,
    pub total_imports: usize,
    pub resolved_imports: usize,
    pub unresolved_imports: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pe::{build_pe_with_imports, build_stub_pe, PeMachine, PeSubsystem};

    #[test]
    fn loader_basic_pe() {
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();

        let result = loader.load(&data, &mut kernel).unwrap();
        assert!(result.mapped_base > 0);
        assert!(loader.is_ready());
        assert!(loader.wow64.as_ref().map_or(false, |w| !w.is_active()));
    }

    #[test]
    fn loader_with_imports() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsGui,
            &[
                ("kernel32.dll", &["GetLastError", "SetLastError", "GetCurrentProcessId"]),
                ("user32.dll", &["CreateWindowExW", "ShowWindow"]),
            ],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();

        let result = loader.load(&data, &mut kernel).unwrap();
        assert_eq!(result.total_imports, 5);
        assert!(result.resolved_imports >= 3);
        assert!(loader.resolution_rate() > 0.5);
    }

    #[test]
    fn loader_builds_peb() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsCui,
            &[("kernel32.dll", &["ExitProcess"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        loader.load(&data, &mut kernel).unwrap();

        let peb = loader.build_peb(1000, "session-01");
        assert_eq!(peb.process_id, 1000);
        assert_eq!(peb.session_id, "session-01");
        assert!(peb.module_list.len() >= 2);
        assert!(peb.find_module("ntdll.dll").is_some());
        assert!(peb.find_module("kernel32.dll").is_some());
    }

    #[test]
    fn loader_builds_teb() {
        let loader = PeLoader::new();
        let teb = loader.build_teb(1, 1000);
        assert_eq!(teb.thread_id, 1);
        assert_eq!(teb.process_id, 1000);
    }

    #[test]
    fn loader_32bit_activates_wow64() {
        let data = build_pe_with_imports(
            PeMachine::I386,
            PeSubsystem::WindowsGui,
            &[("kernel32.dll", &["GetLastError"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        loader.load(&data, &mut kernel).unwrap();

        assert!(loader.wow64.as_ref().unwrap().is_active());
    }

    #[test]
    fn loader_unresolved_imports_reported() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsGui,
            &[("unknown_vendor.dll", &["VendorFunc1", "VendorFunc2"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();

        let result = loader.load(&data, &mut kernel).unwrap();
        assert_eq!(result.unresolved_imports.len(), 2);
        assert!(result.unresolved_imports[0].contains("VendorFunc1"));
    }

    #[test]
    fn loader_invalid_pe_rejected() {
        let data = vec![0x00; 64];
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        assert!(loader.load(&data, &mut kernel).is_err());
    }
}
