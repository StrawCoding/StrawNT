//! Minimal x86-64 CPU loop for strawwu-nt native PE execution.
//!
//! Supports the opcode subset used by the pe1 console fixture (RIP-relative
//! LEA/CALL, MOV imm, SUB/ADD rsp, XOR, and absolute CALL via RAX). Win32
//! stubs in the fixed `STUB_BASE` range produce host-observable side effects.

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::ntdll::{FileAccessMode, NtKernel, NtStatus};

/// Fixed stub page used by the pe1 fixture and PeLoader import map.
pub const STUB_BASE: u64 = 0x7FFE_0000_0000;
pub const STUB_GET_STD_HANDLE: u64 = STUB_BASE;
pub const STUB_WRITE_FILE: u64 = STUB_BASE + 8;
pub const STUB_EXIT_PROCESS: u64 = STUB_BASE + 16;
pub const STUB_CREATE_FILE_A: u64 = STUB_BASE + 24;
pub const STUB_CLOSE_HANDLE: u64 = STUB_BASE + 32;

pub const STD_OUTPUT_HANDLE: i32 = -11;
pub const STD_OUTPUT_MAGIC: u64 = 0x0000_0000_0000_00F5;

const MAX_STEPS: u64 = 100_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CpuHaltReason {
    ExitProcess,
    MaxSteps,
    IllegalInstruction,
    MemoryFault,
    StackFault,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ExecSideEffects {
    pub stdout: Vec<u8>,
    pub stdout_utf8: String,
    pub host_files_written: Vec<String>,
    pub vfs_files_written: Vec<String>,
    pub exit_code: Option<u32>,
    pub instructions_retired: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuRunResult {
    pub halt: CpuHaltReason,
    pub side_effects: ExecSideEffects,
    pub rip: u64,
}

#[derive(Debug, Default)]
struct Gpr {
    rax: u64,
    rcx: u64,
    rdx: u64,
    rbx: u64,
    rsp: u64,
    rbp: u64,
    rsi: u64,
    rdi: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
}

#[derive(Debug)]
pub struct Cpu {
    gpr: Gpr,
    rip: u64,
    stubs: HashMap<u64, String>,
    host_side_effect_dir: Option<PathBuf>,
    side_effects: ExecSideEffects,
    halted: Option<CpuHaltReason>,
    /// Maps guest file handles created via CreateFileA to VFS handle ids.
    open_files: HashMap<u64, u64>,
    next_guest_handle: u64,
}

impl Cpu {
    pub fn new(entry: u64, stack_top: u64) -> Self {
        let mut stubs = HashMap::new();
        stubs.insert(STUB_GET_STD_HANDLE, "GetStdHandle".into());
        stubs.insert(STUB_WRITE_FILE, "WriteFile".into());
        stubs.insert(STUB_EXIT_PROCESS, "ExitProcess".into());
        stubs.insert(STUB_CREATE_FILE_A, "CreateFileA".into());
        stubs.insert(STUB_CLOSE_HANDLE, "CloseHandle".into());

        let mut gpr = Gpr::default();
        gpr.rsp = stack_top;
        Self {
            gpr,
            rip: entry,
            stubs,
            host_side_effect_dir: None,
            side_effects: ExecSideEffects::default(),
            halted: None,
            open_files: HashMap::new(),
            next_guest_handle: 0x2000,
        }
    }

    pub fn with_host_side_effect_dir(mut self, dir: PathBuf) -> Self {
        self.host_side_effect_dir = Some(dir);
        self
    }

    pub fn register_stub(&mut self, addr: u64, name: &str) {
        self.stubs.insert(addr, name.to_string());
    }

    pub fn run(&mut self, kernel: &mut NtKernel) -> CpuRunResult {
        let mut steps = 0u64;
        while self.halted.is_none() && steps < MAX_STEPS {
            if let Err(reason) = self.step(kernel) {
                self.halted = Some(reason);
                break;
            }
            steps += 1;
            self.side_effects.instructions_retired = steps;
        }
        if self.halted.is_none() {
            self.halted = Some(CpuHaltReason::MaxSteps);
        }
        CpuRunResult {
            halt: self.halted.unwrap(),
            side_effects: self.side_effects.clone(),
            rip: self.rip,
        }
    }

    fn step(&mut self, kernel: &mut NtKernel) -> Result<(), CpuHaltReason> {
        let b0 = kernel
            .memory
            .read_u8(self.rip)
            .map_err(|_| CpuHaltReason::MemoryFault)?;

        let mut rex_w = false;
        let mut rex_r = false;
        let mut rex_b = false;
        let mut ip = self.rip;
        let mut op = b0;
        if (b0 & 0xF0) == 0x40 {
            rex_w = (b0 & 0x08) != 0;
            rex_r = (b0 & 0x04) != 0;
            rex_b = (b0 & 0x01) != 0;
            ip += 1;
            op = kernel
                .memory
                .read_u8(ip)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
        }

        // sub/add rsp, imm8 — 48 83 EC/C4 ib
        if rex_w && op == 0x83 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            let imm = kernel
                .memory
                .read_u8(ip + 2)
                .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
            if modrm == 0xEC {
                self.gpr.rsp = self.gpr.rsp.wrapping_add((-imm) as u64);
                self.rip = ip + 3;
                return Ok(());
            }
            if modrm == 0xC4 {
                self.gpr.rsp = self.gpr.rsp.wrapping_add(imm as u64);
                self.rip = ip + 3;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov r64, imm64 — REX.W B8+rd iq
        if rex_w && (op & 0xF8) == 0xB8 {
            let reg = (op & 0x07) as usize + if rex_b { 8 } else { 0 };
            let imm = kernel
                .memory
                .read_u64(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            self.set_gpr(reg, imm);
            self.rip = ip + 9;
            return Ok(());
        }

        // mov r32, imm32 — B8+rd id (zero-extends); REX.B selects r8-r15
        if (op & 0xF8) == 0xB8 {
            let reg = (op & 0x07) as usize + if rex_b { 8 } else { 0 };
            let imm = kernel
                .memory
                .read_u32(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)? as u64;
            self.set_gpr(reg, imm);
            self.rip = ip + 5;
            return Ok(());
        }

        // xor r32, r/m32 — 31 /r
        if op == 0x31 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if modrm == 0xC9 {
                self.gpr.rcx = 0;
                self.rip = ip + 2;
                return Ok(());
            }
            if modrm == 0xC0 {
                self.gpr.rax = 0;
                self.rip = ip + 2;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov rcx, rax — 48 89 C1
        if rex_w && op == 0x89 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if modrm == 0xC1 {
                self.gpr.rcx = self.gpr.rax;
                self.rip = ip + 2;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // lea r64, [rip+disp32] — 48/4C 8D 05/0D/15/1D (modrm rm=101)
        if op == 0x8D {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if (modrm & 0xC7) == 0x05 {
                let reg = ((modrm >> 3) & 0x07) as usize + if rex_r { 8 } else { 0 };
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let addr = (ip as i64 + 6 + disp) as u64;
                self.set_gpr(reg, addr);
                self.rip = ip + 6;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov qword [rsp+disp8], imm32 — 48 C7 44 24 disp imm32
        if rex_w && op == 0xC7 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            let sib = kernel
                .memory
                .read_u8(ip + 2)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if modrm == 0x44 && sib == 0x24 {
                let disp = kernel
                    .memory
                    .read_u8(ip + 3)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
                let imm = kernel
                    .memory
                    .read_u32(ip + 4)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as u64;
                let addr = (self.gpr.rsp as i64 + disp) as u64;
                kernel
                    .memory
                    .write_u64(addr, imm)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 8;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // call rax / call [rip+disp32]
        if op == 0xFF {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if modrm == 0xD0 {
                let target = self.gpr.rax;
                self.rip = ip + 2;
                return self.call_target(kernel, target);
            }
            if modrm == 0x15 {
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let slot = (ip as i64 + 6 + disp) as u64;
                let target = kernel
                    .memory
                    .read_u64(slot)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 6;
                return self.call_target(kernel, target);
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // ret — C3
        if op == 0xC3 {
            let ret = kernel
                .memory
                .read_u64(self.gpr.rsp)
                .map_err(|_| CpuHaltReason::StackFault)?;
            self.gpr.rsp = self.gpr.rsp.wrapping_add(8);
            self.rip = ret;
            return Ok(());
        }

        Err(CpuHaltReason::IllegalInstruction)
    }

    fn call_target(&mut self, kernel: &mut NtKernel, target: u64) -> Result<(), CpuHaltReason> {
        if let Some(name) = self.stubs.get(&target).cloned() {
            return self.dispatch_stub(kernel, &name);
        }
        // Near call into guest: push return, jump
        let ret = self.rip;
        self.gpr.rsp = self.gpr.rsp.wrapping_sub(8);
        kernel
            .memory
            .write_u64(self.gpr.rsp, ret)
            .map_err(|_| CpuHaltReason::StackFault)?;
        self.rip = target;
        Ok(())
    }

    fn dispatch_stub(&mut self, kernel: &mut NtKernel, name: &str) -> Result<(), CpuHaltReason> {
        match name {
            "GetStdHandle" => {
                let nstd = self.gpr.rcx as i32;
                self.gpr.rax = if nstd == STD_OUTPUT_HANDLE {
                    STD_OUTPUT_MAGIC
                } else {
                    0
                };
                Ok(())
            }
            "WriteFile" => {
                let handle = self.gpr.rcx;
                let buf_ptr = self.gpr.rdx;
                let len = self.gpr.r8 as usize;
                let written_ptr = self.gpr.r9;
                let data = kernel
                    .memory
                    .read_bytes(buf_ptr, len)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;

                if handle == STD_OUTPUT_MAGIC {
                    self.side_effects.stdout.extend_from_slice(&data);
                    self.side_effects.stdout_utf8 =
                        String::from_utf8_lossy(&self.side_effects.stdout).into_owned();
                    if let Some(dir) = &self.host_side_effect_dir {
                        let path = dir.join("pe-stdout.txt");
                        if let Some(parent) = path.parent() {
                            let _ = std::fs::create_dir_all(parent);
                        }
                        let _ = std::fs::write(&path, &self.side_effects.stdout);
                        let p = path.display().to_string();
                        if !self.side_effects.host_files_written.contains(&p) {
                            self.side_effects.host_files_written.push(p);
                        }
                    }
                } else if let Some(vfs_h) = self.open_files.get(&handle).copied() {
                    let _ = kernel
                        .filesystem
                        .write_file(crate::ntdll::FileHandle(vfs_h), &data);
                    if let Some(dir) = &self.host_side_effect_dir {
                        if let Some(vf) = kernel
                            .filesystem
                            .handle_path(crate::ntdll::FileHandle(vfs_h))
                        {
                            let host_name = vf
                                .rsplit('\\')
                                .next()
                                .unwrap_or("pe-out.bin")
                                .to_string();
                            let path = dir.join(host_name);
                            let _ = std::fs::write(&path, &data);
                            self.side_effects
                                .host_files_written
                                .push(path.display().to_string());
                            self.side_effects.vfs_files_written.push(vf);
                        }
                    }
                }

                if written_ptr != 0 {
                    let _ = kernel.memory.write_u32(written_ptr, len as u32);
                }
                self.gpr.rax = 1; // BOOL TRUE
                Ok(())
            }
            "CreateFileA" => {
                let path_ptr = self.gpr.rcx;
                let path = read_guest_cstring(kernel, path_ptr, 260)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let win_path = if path.contains(':') || path.starts_with('\\') {
                    path.clone()
                } else {
                    format!(r"C:\Users\StrawWU\{path}")
                };
                let fh = kernel
                    .filesystem
                    .create_file(&win_path, FileAccessMode::ReadWrite)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let guest = self.next_guest_handle;
                self.next_guest_handle += 1;
                self.open_files.insert(guest, fh.0);
                self.gpr.rax = guest;
                Ok(())
            }
            "CloseHandle" => {
                let handle = self.gpr.rcx;
                if let Some(vfs_h) = self.open_files.remove(&handle) {
                    let _ = kernel
                        .filesystem
                        .close_handle(crate::ntdll::FileHandle(vfs_h));
                }
                self.gpr.rax = 1;
                Ok(())
            }
            "ExitProcess" => {
                let code = self.gpr.rcx as u32;
                self.side_effects.exit_code = Some(code);
                self.halted = Some(CpuHaltReason::ExitProcess);
                Ok(())
            }
            _ => Err(CpuHaltReason::IllegalInstruction),
        }
    }

    fn set_gpr(&mut self, idx: usize, val: u64) {
        match idx {
            0 => self.gpr.rax = val,
            1 => self.gpr.rcx = val,
            2 => self.gpr.rdx = val,
            3 => self.gpr.rbx = val,
            4 => self.gpr.rsp = val,
            5 => self.gpr.rbp = val,
            6 => self.gpr.rsi = val,
            7 => self.gpr.rdi = val,
            8 => self.gpr.r8 = val,
            9 => self.gpr.r9 = val,
            10 => self.gpr.r10 = val,
            11 => self.gpr.r11 = val,
            12 => self.gpr.r12 = val,
            13 => self.gpr.r13 = val,
            14 => self.gpr.r14 = val,
            15 => self.gpr.r15 = val,
            _ => {}
        }
    }
}

fn read_guest_cstring(kernel: &NtKernel, ptr: u64, max: usize) -> Result<String, NtStatus> {
    let mut bytes = Vec::new();
    for i in 0..max {
        let b = kernel.memory.read_u8(ptr + i as u64)?;
        if b == 0 {
            break;
        }
        bytes.push(b);
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

/// Run mapped PE image from `entry` with a fresh stack in `kernel.memory`.
pub fn run_entry(
    kernel: &mut NtKernel,
    entry: u64,
    host_side_effect_dir: Option<PathBuf>,
) -> Result<CpuRunResult, NtStatus> {
    let stack_base = kernel
        .memory
        .allocate(0x1_0000, crate::ntdll::MemoryProtection::ReadWrite)?;
    let stack_top = stack_base + 0x1_0000 - 0x20;
    // Sentinel return address
    kernel.memory.write_u64(stack_top, 0)?;

    let mut cpu = Cpu::new(entry, stack_top);
    if let Some(dir) = host_side_effect_dir {
        cpu = cpu.with_host_side_effect_dir(dir);
    }
    Ok(cpu.run(kernel))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ntdll::MemoryProtection;
    use crate::pe::build_real_console_fixture_pe;
    use crate::loader::PeLoader;

    #[test]
    fn cpu_runs_fixture_with_stdout_side_effect() {
        let pe = build_real_console_fixture_pe();
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let load = loader.load(&pe, &mut kernel).unwrap();
        let tmp = std::env::temp_dir().join("strawwu-pe1-cpu-test");
        let _ = std::fs::create_dir_all(&tmp);
        let result = run_entry(&mut kernel, load.entry_point_va, Some(tmp.clone())).unwrap();
        assert_eq!(result.halt, CpuHaltReason::ExitProcess);
        assert!(
            result.side_effects.stdout_utf8.contains("STRAWWU_PE_REAL_OK"),
            "stdout={}",
            result.side_effects.stdout_utf8
        );
        assert_eq!(result.side_effects.exit_code, Some(0));
        assert!(result.side_effects.instructions_retired > 0);
        let host = tmp.join("pe-stdout.txt");
        assert!(host.is_file(), "missing {}", host.display());
        let body = std::fs::read_to_string(&host).unwrap();
        assert!(body.contains("STRAWWU_PE_REAL_OK"));
    }

    #[test]
    fn memory_read_write_roundtrip() {
        let mut kernel = NtKernel::new();
        let base = kernel
            .memory
            .allocate(0x1000, MemoryProtection::ReadWrite)
            .unwrap();
        kernel.memory.write_bytes(base, b"hello").unwrap();
        assert_eq!(kernel.memory.read_bytes(base, 5).unwrap(), b"hello");
    }
}
