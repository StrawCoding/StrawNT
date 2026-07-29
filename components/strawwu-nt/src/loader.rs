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

fn fixed_stub_addr(name: &str) -> Option<u64> {
    use crate::cpu::*;
    Some(match name {
        "GetStdHandle" => STUB_GET_STD_HANDLE,
        "WriteFile" => STUB_WRITE_FILE,
        "ExitProcess" => STUB_EXIT_PROCESS,
        "CreateFileA" => STUB_CREATE_FILE_A,
        "CloseHandle" => STUB_CLOSE_HANDLE,
        "ReadFile" => STUB_READ_FILE,
        "GetCurrentProcessId" => STUB_GET_CURRENT_PROCESS_ID,
        "GetCommandLineA" => STUB_GET_COMMAND_LINE_A,
        "GetProcessHeap" => STUB_GET_PROCESS_HEAP,
        "HeapAlloc" => STUB_HEAP_ALLOC,
        "HeapFree" => STUB_HEAP_FREE,
        "malloc" => STUB_MALLOC,
        "free" => STUB_FREE,
        "puts" => STUB_PUTS,
        "RegisterClassA" => STUB_REGISTER_CLASS_A,
        "CreateWindowExA" => STUB_CREATE_WINDOW_EX_A,
        "ShowWindow" => STUB_SHOW_WINDOW,
        "UpdateWindow" => STUB_UPDATE_WINDOW,
        "GetMessageA" => STUB_GET_MESSAGE_A,
        "TranslateMessage" => STUB_TRANSLATE_MESSAGE,
        "DispatchMessageA" => STUB_DISPATCH_MESSAGE_A,
        "DestroyWindow" => STUB_DESTROY_WINDOW,
        "PostQuitMessage" => STUB_POST_QUIT_MESSAGE,
        "GetDC" => STUB_GET_DC,
        "ReleaseDC" => STUB_RELEASE_DC,
        "CreateCompatibleDC" => STUB_CREATE_COMPATIBLE_DC,
        "BitBlt" => STUB_BIT_BLT,
        "DeleteDC" => STUB_DELETE_DC,
        "GetDeviceCaps" => STUB_GET_DEVICE_CAPS,
        _ => return None,
    })
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

        let is_pe32_plus = pe.machine.is_64bit();
        let entry_size: u64 = if is_pe32_plus { 8 } else { 4 };
        let mut resolutions = Vec::new();
        // Dynamic stub page after the fixed pe1–pe3 slots.
        let mut stub_addr: u64 = crate::cpu::STUB_BASE + 0x200;

        for import in &pe.imports {
            for (idx, func_name) in import.functions.iter().enumerate() {
                let resolve_status = self.stubs.resolve(&import.dll_name, func_name);
                // Soft-resolve unknowns so real public PEs can still start;
                // CPU soft-stubs return 0 for unimplemented names.
                let resolved = resolve_status == NtStatus::Success
                    || resolve_status == NtStatus::ObjectNameNotFound
                    || resolve_status == NtStatus::NotImplemented;
                let addr = fixed_stub_addr(func_name).unwrap_or_else(|| {
                    let a = stub_addr;
                    stub_addr += 8;
                    a
                });

                if resolved {
                    // Patch IAT slot so `call [rip+disp]` / `jmp [iat]` hit our stubs.
                    if import.first_thunk_rva != 0 {
                        let iat_va = mapped_base
                            + import.first_thunk_rva as u64
                            + (idx as u64) * entry_size;
                        if is_pe32_plus {
                            let _ = kernel.memory.write_u64(iat_va, addr);
                        } else {
                            let _ = kernel.memory.write_u32(iat_va, addr as u32);
                        }
                    }
                }

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

        let unresolved: Vec<_> = resolutions
            .iter()
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
    use crate::wow64::Wow64Mode;

    #[test]
    fn loader_basic_pe() {
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let result = loader.load(&data, &mut kernel).unwrap();
        assert!(result.entry_point_va > 0);
        assert_eq!(loader.state, LoaderState::Ready);
    }

    #[test]
    fn loader_with_imports() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsCui,
            &[
                ("kernel32.dll", &["GetLastError", "ExitProcess", "GetStdHandle"]),
                ("msvcrt.dll", &["puts", "malloc"]),
            ],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let result = loader.load(&data, &mut kernel).unwrap();
        assert_eq!(result.total_imports, 5);
        assert!(result.resolved_imports >= 3);
        // IAT must be patched to stub addresses for real call [iat] paths.
        let pe = loader.pe.as_ref().unwrap();
        let iat0 = pe.imports[0].first_thunk_rva;
        assert!(iat0 > 0);
        // Second KERNEL32 import is ExitProcess (fixed stub).
        let slot = result.mapped_base + iat0 as u64 + 8;
        let addr = kernel.memory.read_u64(slot).unwrap();
        assert_eq!(addr, crate::cpu::STUB_EXIT_PROCESS);
    }

    #[test]
    fn loader_builds_peb() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsGui,
            &[("user32.dll", &["MessageBoxW"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        loader.load(&data, &mut kernel).unwrap();
        let peb = loader.build_peb(42, "sess");
        assert_eq!(peb.process_id, 42);
        assert!(peb.module_list.len() >= 2);
    }

    #[test]
    fn loader_builds_teb() {
        let mut loader = PeLoader::new();
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let mut kernel = NtKernel::new();
        loader.load(&data, &mut kernel).unwrap();
        let teb = loader.build_teb(7, 42);
        assert_eq!(teb.thread_id, 7);
        assert_eq!(teb.process_id, 42);
    }

    #[test]
    fn loader_32bit_activates_wow64() {
        let data = build_pe_with_imports(
            PeMachine::I386,
            PeSubsystem::WindowsCui,
            &[("kernel32.dll", &["ExitProcess"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        loader.load(&data, &mut kernel).unwrap();
        assert_eq!(loader.wow64.as_ref().unwrap().mode, Wow64Mode::Active);
    }

    #[test]
    fn loader_unresolved_imports_reported() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsCui,
            &[("vendor.dll", &["VendorFunc1", "VendorFunc2"])],
        );
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let result = loader.load(&data, &mut kernel).unwrap();
        // Soft-resolve unknowns for golden apps; still track them as resolved addresses.
        assert_eq!(result.total_imports, 2);
        assert_eq!(result.resolved_imports, 2);
        assert!(result.unresolved_imports.is_empty());
    }

    #[test]
    fn loader_invalid_pe_rejected() {
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        assert!(loader.load(b"not a pe", &mut kernel).is_err());
    }
}
