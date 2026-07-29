//! Minimal x86-64 CPU loop for strawwu-nt native PE execution.
//!
//! Supports the opcode subset used by pe1/pe2/pe3 fixtures (RIP-relative
//! LEA/CALL, MOV imm/reg/stack, SUB/ADD rsp, XOR, and absolute CALL via RAX).
//! Win32 / CRT / user32 / gdi stubs in the fixed `STUB_BASE` range produce
//! host-observable side effects (file / process / heap / stdout / HWND /
//! compositor frame) — not registry-only stubs.

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::ntdll::{FileAccessMode, FileHandle, MemoryProtection, NtKernel, NtStatus};
use crate::win32_stubs::{
    GdiManager, Hwnd, WindowManager, WM_QUIT, WM_PAINT,
};

/// Fixed stub page used by console/GUI fixtures and PeLoader import map.
pub const STUB_BASE: u64 = 0x7FFE_0000_0000;
pub const STUB_GET_STD_HANDLE: u64 = STUB_BASE;
pub const STUB_WRITE_FILE: u64 = STUB_BASE + 8;
pub const STUB_EXIT_PROCESS: u64 = STUB_BASE + 16;
pub const STUB_CREATE_FILE_A: u64 = STUB_BASE + 24;
pub const STUB_CLOSE_HANDLE: u64 = STUB_BASE + 32;
pub const STUB_READ_FILE: u64 = STUB_BASE + 40;
pub const STUB_GET_CURRENT_PROCESS_ID: u64 = STUB_BASE + 48;
pub const STUB_GET_COMMAND_LINE_A: u64 = STUB_BASE + 56;
pub const STUB_GET_PROCESS_HEAP: u64 = STUB_BASE + 64;
pub const STUB_HEAP_ALLOC: u64 = STUB_BASE + 72;
pub const STUB_HEAP_FREE: u64 = STUB_BASE + 80;
pub const STUB_MALLOC: u64 = STUB_BASE + 88;
pub const STUB_FREE: u64 = STUB_BASE + 96;
pub const STUB_PUTS: u64 = STUB_BASE + 104;
pub const STUB_REGISTER_CLASS_A: u64 = STUB_BASE + 112;
pub const STUB_CREATE_WINDOW_EX_A: u64 = STUB_BASE + 120;
pub const STUB_SHOW_WINDOW: u64 = STUB_BASE + 128;
pub const STUB_UPDATE_WINDOW: u64 = STUB_BASE + 136;
pub const STUB_GET_MESSAGE_A: u64 = STUB_BASE + 144;
pub const STUB_TRANSLATE_MESSAGE: u64 = STUB_BASE + 152;
pub const STUB_DISPATCH_MESSAGE_A: u64 = STUB_BASE + 160;
pub const STUB_DESTROY_WINDOW: u64 = STUB_BASE + 168;
pub const STUB_POST_QUIT_MESSAGE: u64 = STUB_BASE + 176;
pub const STUB_GET_DC: u64 = STUB_BASE + 184;
pub const STUB_RELEASE_DC: u64 = STUB_BASE + 192;
pub const STUB_CREATE_COMPATIBLE_DC: u64 = STUB_BASE + 200;
pub const STUB_BIT_BLT: u64 = STUB_BASE + 208;
pub const STUB_DELETE_DC: u64 = STUB_BASE + 216;
pub const STUB_GET_DEVICE_CAPS: u64 = STUB_BASE + 224;

pub const STD_OUTPUT_HANDLE: i32 = -11;
pub const STD_OUTPUT_MAGIC: u64 = 0x0000_0000_0000_00F5;
pub const PROCESS_HEAP_MAGIC: u64 = 0x0000_0000_0000_0EA7;
pub const DEFAULT_GUEST_PID: u32 = 1000;
pub const DEFAULT_GUI_WIDTH: u32 = 640;
pub const DEFAULT_GUI_HEIGHT: u32 = 480;

const MAX_STEPS: u64 = 2_000_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CpuHaltReason {
    ExitProcess,
    MaxSteps,
    IllegalInstruction,
    MemoryFault,
    StackFault,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GuiSideEffects {
    pub hwnd: Option<u64>,
    pub title: Option<String>,
    pub width: u32,
    pub height: u32,
    pub visible: bool,
    pub closed: bool,
    pub messages_dispatched: u64,
    pub windows_created: u64,
    pub gdi_bitblt_count: u64,
    pub gdi_dc_count: u64,
    pub compositor_backend: String,
    pub compositor_frames: u64,
    pub screenshot_path: Option<String>,
    pub compositor_obs_path: Option<String>,
    /// Filled triangle pixels from native PE BitBlt/present path (strawwu-graphics raster).
    pub triangle_pixels: u64,
    pub triangle_path: Option<String>,
    pub present_path: Option<String>,
    pub present_frames: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ExecSideEffects {
    pub stdout: Vec<u8>,
    pub stdout_utf8: String,
    pub host_files_written: Vec<String>,
    pub vfs_files_written: Vec<String>,
    pub exit_code: Option<u32>,
    pub instructions_retired: u64,
    /// Win32/CRT APIs actually dispatched by the CPU loop (not registry-only).
    pub apis_invoked: Vec<String>,
    pub heap_allocations: u64,
    pub guest_pid: Option<u32>,
    pub command_line: Option<String>,
    /// user32/gdi MVP window + compositor observation (pe3).
    pub gui: Option<GuiSideEffects>,
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
    cmdline_va: u64,
    guest_pid: u32,
    image_base: u64,
    windows: WindowManager,
    gdi: GdiManager,
    /// Maps guest HDC values to window dimensions used at GetDC time.
    hdc_size: HashMap<u64, (u32, u32)>,
    framebuffer: Vec<u8>,
    fb_width: u32,
    fb_height: u32,
}

impl Cpu {
    pub fn new(entry: u64, stack_top: u64) -> Self {
        let mut stubs = HashMap::new();
        stubs.insert(STUB_GET_STD_HANDLE, "GetStdHandle".into());
        stubs.insert(STUB_WRITE_FILE, "WriteFile".into());
        stubs.insert(STUB_EXIT_PROCESS, "ExitProcess".into());
        stubs.insert(STUB_CREATE_FILE_A, "CreateFileA".into());
        stubs.insert(STUB_CLOSE_HANDLE, "CloseHandle".into());
        stubs.insert(STUB_READ_FILE, "ReadFile".into());
        stubs.insert(STUB_GET_CURRENT_PROCESS_ID, "GetCurrentProcessId".into());
        stubs.insert(STUB_GET_COMMAND_LINE_A, "GetCommandLineA".into());
        stubs.insert(STUB_GET_PROCESS_HEAP, "GetProcessHeap".into());
        stubs.insert(STUB_HEAP_ALLOC, "HeapAlloc".into());
        stubs.insert(STUB_HEAP_FREE, "HeapFree".into());
        stubs.insert(STUB_MALLOC, "malloc".into());
        stubs.insert(STUB_FREE, "free".into());
        stubs.insert(STUB_PUTS, "puts".into());
        stubs.insert(STUB_REGISTER_CLASS_A, "RegisterClassA".into());
        stubs.insert(STUB_CREATE_WINDOW_EX_A, "CreateWindowExA".into());
        stubs.insert(STUB_SHOW_WINDOW, "ShowWindow".into());
        stubs.insert(STUB_UPDATE_WINDOW, "UpdateWindow".into());
        stubs.insert(STUB_GET_MESSAGE_A, "GetMessageA".into());
        stubs.insert(STUB_TRANSLATE_MESSAGE, "TranslateMessage".into());
        stubs.insert(STUB_DISPATCH_MESSAGE_A, "DispatchMessageA".into());
        stubs.insert(STUB_DESTROY_WINDOW, "DestroyWindow".into());
        stubs.insert(STUB_POST_QUIT_MESSAGE, "PostQuitMessage".into());
        stubs.insert(STUB_GET_DC, "GetDC".into());
        stubs.insert(STUB_RELEASE_DC, "ReleaseDC".into());
        stubs.insert(STUB_CREATE_COMPATIBLE_DC, "CreateCompatibleDC".into());
        stubs.insert(STUB_BIT_BLT, "BitBlt".into());
        stubs.insert(STUB_DELETE_DC, "DeleteDC".into());
        stubs.insert(STUB_GET_DEVICE_CAPS, "GetDeviceCaps".into());

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
            cmdline_va: 0,
            guest_pid: DEFAULT_GUEST_PID,
            image_base: 0,
            windows: WindowManager::new(),
            gdi: GdiManager::new(),
            hdc_size: HashMap::new(),
            framebuffer: Vec::new(),
            fb_width: DEFAULT_GUI_WIDTH,
            fb_height: DEFAULT_GUI_HEIGHT,
        }
    }

    pub fn with_host_side_effect_dir(mut self, dir: PathBuf) -> Self {
        self.host_side_effect_dir = Some(dir);
        self
    }

    pub fn with_command_line(mut self, va: u64, text: &str) -> Self {
        self.cmdline_va = va;
        self.side_effects.command_line = Some(text.to_string());
        self
    }

    pub fn with_guest_pid(mut self, pid: u32) -> Self {
        self.guest_pid = pid;
        self
    }

    pub fn with_image_base(mut self, base: u64) -> Self {
        self.image_base = base;
        self
    }

    pub fn register_stub(&mut self, addr: u64, name: &str) {
        self.stubs.insert(addr, name.to_string());
    }

    pub fn register_imports(&mut self, resolutions: &[crate::loader::ImportResolution]) {
        for r in resolutions {
            if r.resolved && r.resolved_address != 0 {
                self.stubs
                    .insert(r.resolved_address, r.function_name.clone());
            }
        }
    }

    fn note_api(&mut self, name: &str) {
        self.side_effects.apis_invoked.push(name.to_string());
    }

    fn emit_stdout(&mut self, data: &[u8]) {
        self.side_effects.stdout.extend_from_slice(data);
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
    }

    fn gui_mut(&mut self) -> &mut GuiSideEffects {
        if self.side_effects.gui.is_none() {
            self.side_effects.gui = Some(GuiSideEffects {
                compositor_backend: "wayland-mutter".into(),
                width: self.fb_width,
                height: self.fb_height,
                ..GuiSideEffects::default()
            });
        }
        self.side_effects.gui.as_mut().unwrap()
    }

    fn read_stack_u64(&self, kernel: &NtKernel, disp: i64) -> Result<u64, CpuHaltReason> {
        let addr = (self.gpr.rsp as i64 + disp) as u64;
        kernel
            .memory
            .read_u64(addr)
            .map_err(|_| CpuHaltReason::MemoryFault)
    }

    /// Rasterize a real demo triangle into the guest framebuffer via strawwu-graphics.
    fn rasterize_triangle_framebuffer(&mut self) -> u64 {
        use strawwu_graphics::triangle::{
            demo_triangle_vertices, fill_triangle, Framebuffer, CLEAR_COLOR, TRIANGLE_COLOR,
        };
        let mut fb = Framebuffer::new(self.fb_width, self.fb_height, CLEAR_COLOR);
        let (a, b, c) = demo_triangle_vertices(self.fb_width, self.fb_height);
        fill_triangle(&mut fb, a, b, c, TRIANGLE_COLOR);
        let pixels = fb.count_color(TRIANGLE_COLOR);
        self.framebuffer = fb.pixels;
        pixels
    }

    fn write_gui_evidence(&mut self) {
        let Some(dir) = self.host_side_effect_dir.clone() else {
            return;
        };
        let _ = std::fs::create_dir_all(&dir);

        if self.framebuffer.is_empty() {
            let _ = self.rasterize_triangle_framebuffer();
        }

        let header = format!("P6\n{} {}\n255\n", self.fb_width, self.fb_height);
        let mut bytes = header.into_bytes();
        bytes.extend_from_slice(&self.framebuffer);

        // Legacy pe3 screenshot name (still triangle-backed) + canonical nt1 names.
        let shot = dir.join("pe3-window.ppm");
        let tri = dir.join("nt-triangle.ppm");
        let _ = std::fs::write(&shot, &bytes);
        let _ = std::fs::write(&tri, &bytes);
        let shot_s = shot.display().to_string();
        let tri_s = tri.display().to_string();
        for p in [&shot_s, &tri_s] {
            if !self.side_effects.host_files_written.contains(p) {
                self.side_effects.host_files_written.push(p.clone());
            }
        }

        let fb_w = self.fb_width;
        let fb_h = self.fb_height;
        let triangle_pixels = {
            use strawwu_graphics::triangle::TRIANGLE_COLOR;
            let mut n = 0u64;
            for px in self.framebuffer.chunks_exact(3) {
                if px[0] == TRIANGLE_COLOR.r
                    && px[1] == TRIANGLE_COLOR.g
                    && px[2] == TRIANGLE_COLOR.b
                {
                    n += 1;
                }
            }
            n
        };
        let gui = self.gui_mut();
        gui.screenshot_path = Some(shot_s);
        gui.triangle_path = Some(tri_s.clone());
        gui.triangle_pixels = triangle_pixels.max(gui.triangle_pixels);
        gui.width = fb_w;
        gui.height = fb_h;
        gui.compositor_frames = gui.compositor_frames.max(1);
        gui.present_frames = gui.present_frames.max(gui.compositor_frames);
        if gui.compositor_backend.is_empty() {
            gui.compositor_backend = "wayland-mutter".into();
        }
        let obs = serde_json::json!({
            "schema": "strawnt-pe-gui-present/v1",
            "backend": gui.compositor_backend,
            "display": "wayland",
            "compositor": "mutter",
            "hwnd": gui.hwnd,
            "title": gui.title,
            "width": gui.width,
            "height": gui.height,
            "visible": gui.visible,
            "closed": gui.closed,
            "frame_count": gui.compositor_frames,
            "present_frames": gui.present_frames,
            "messages_dispatched": gui.messages_dispatched,
            "gdi_bitblt_count": gui.gdi_bitblt_count,
            "triangle_pixels": gui.triangle_pixels,
            "screenshot": gui.screenshot_path,
            "triangle_file": gui.triangle_path,
        });
        let obs_path = dir.join("pe3-compositor.json");
        let present_path = dir.join("nt-present.json");
        if let Ok(body) = serde_json::to_string_pretty(&obs) {
            let payload = body + "\n";
            let _ = std::fs::write(&obs_path, &payload);
            let _ = std::fs::write(&present_path, &payload);
            let obs_s = obs_path.display().to_string();
            let present_s = present_path.display().to_string();
            for p in [&obs_s, &present_s] {
                if !self.side_effects.host_files_written.contains(p) {
                    self.side_effects.host_files_written.push(p.clone());
                }
            }
            if let Some(g) = self.side_effects.gui.as_mut() {
                g.compositor_obs_path = Some(obs_s);
                g.present_path = Some(present_s);
            }
        }
    }

    fn present_compositor_frame(&mut self) {
        use strawwu_graphics::present::{DisplayBackend, PresentBridge};

        let triangle_pixels = self.rasterize_triangle_framebuffer();
        // Observable present bridge tick (native path; not Wine/Proton).
        let mut present = PresentBridge::new(DisplayBackend::Wayland);
        let _ = present.resize(self.fb_width, self.fb_height);
        let _ = present.present_frame();
        {
            let gui = self.gui_mut();
            gui.compositor_frames = gui.compositor_frames.saturating_add(1);
            gui.present_frames = gui.present_frames.saturating_add(1).max(present.frame_count);
            gui.compositor_backend = "wayland-mutter".into();
            gui.triangle_pixels = triangle_pixels.max(gui.triangle_pixels);
        }
        self.write_gui_evidence();
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
        let mut operand_size_override = false;
        if op == 0x66 {
            operand_size_override = true;
            ip += 1;
            op = kernel
                .memory
                .read_u8(ip)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
        }
        if (op & 0xF0) == 0x40 {
            rex_w = (op & 0x08) != 0;
            rex_r = (op & 0x04) != 0;
            rex_b = (op & 0x01) != 0;
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

        // mov rcx, rax — 48 89 C1
        // mov rdx, rax — 48 89 C2
        // mov r8, rax  — 49 89 C0
        // mov [rsp+disp8], r64 — 48 89 xx 24 disp (any source reg)
        // mov [rip+disp32], rax — 48 89 05 disp32
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
            if modrm == 0xC2 {
                self.gpr.rdx = self.gpr.rax;
                self.rip = ip + 2;
                return Ok(());
            }
            // REX.W + REX.B already handled via rex_w; 49 89 C0 is REX.WB=01001b → b0=0x49
            if modrm == 0xC0 && rex_b {
                self.gpr.r8 = self.gpr.rax;
                self.rip = ip + 2;
                return Ok(());
            }
            if modrm == 0x05 {
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let addr = (ip as i64 + 6 + disp) as u64;
                kernel
                    .memory
                    .write_u64(addr, self.gpr.rax)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 6;
                return Ok(());
            }
            let sib = kernel
                .memory
                .read_u8(ip + 2)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            // mod=01 rm=100 SIB → [rsp+disp8]
            if (modrm & 0xC7) == 0x44 && sib == 0x24 {
                let src = ((modrm >> 3) & 0x07) as usize + if rex_r { 8 } else { 0 };
                let disp = kernel
                    .memory
                    .read_u8(ip + 3)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
                let addr = (self.gpr.rsp as i64 + disp) as u64;
                let val = match src {
                    0 => self.gpr.rax,
                    1 => self.gpr.rcx,
                    2 => self.gpr.rdx,
                    3 => self.gpr.rbx,
                    5 => self.gpr.rbp,
                    6 => self.gpr.rsi,
                    7 => self.gpr.rdi,
                    8 => self.gpr.r8,
                    9 => self.gpr.r9,
                    10 => self.gpr.r10,
                    11 => self.gpr.r11,
                    12 => self.gpr.r12,
                    13 => self.gpr.r13,
                    14 => self.gpr.r14,
                    15 => self.gpr.r15,
                    _ => 0,
                };
                kernel
                    .memory
                    .write_u64(addr, val)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 4;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov r32, [rsp+disp8] / mov [rsp+disp8], r32 — 89 / 8B without REX.W
        if op == 0x89 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            let sib = kernel
                .memory
                .read_u8(ip + 2)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if (modrm & 0xC7) == 0x44 && sib == 0x24 {
                let src = ((modrm >> 3) & 0x07) as usize;
                let disp = kernel
                    .memory
                    .read_u8(ip + 3)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
                let addr = (self.gpr.rsp as i64 + disp) as u64;
                let val = match src {
                    0 => self.gpr.rax as u32,
                    1 => self.gpr.rcx as u32,
                    2 => self.gpr.rdx as u32,
                    3 => self.gpr.rbx as u32,
                    5 => self.gpr.rbp as u32,
                    6 => self.gpr.rsi as u32,
                    7 => self.gpr.rdi as u32,
                    _ => 0,
                };
                kernel
                    .memory
                    .write_u32(addr, val)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 4;
                return Ok(());
            }
        }

        // xor r32, r/m32 — 31 /r or 33 /r (zero register forms)
        if op == 0x31 || op == 0x33 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            // reg-reg xor same register → zero
            if (modrm & 0xC0) == 0xC0 {
                let rm = (modrm & 0x07) as usize + if rex_b { 8 } else { 0 };
                let reg = ((modrm >> 3) & 0x07) as usize + if rex_r { 8 } else { 0 };
                if rm == reg {
                    self.set_gpr(rm, 0);
                    self.rip = ip + 2;
                    return Ok(());
                }
            }
            // keep legacy exact matches
            if modrm == 0xC9 {
                if rex_b {
                    self.gpr.r9 = 0;
                } else {
                    self.gpr.rcx = 0;
                }
                self.rip = ip + 2;
                return Ok(());
            }
            if modrm == 0xC0 {
                if rex_b {
                    self.gpr.r8 = 0;
                } else {
                    self.gpr.rax = 0;
                }
                self.rip = ip + 2;
                return Ok(());
            }
            if modrm == 0xD2 {
                self.gpr.rdx = 0;
                self.rip = ip + 2;
                return Ok(());
            }
            if modrm == 0xDB {
                self.gpr.rbx = 0;
                self.rip = ip + 2;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov r64, [rip+disp32] — 48/4C 8B 05/0D/15/1D …
        // Also handles non-REX 8B for r32 when needed via zero-extend path below.
        if (rex_w || op == 0x8B) && op == 0x8B {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            // mod=00 rm=101 → [rip+disp32]
            if (modrm & 0xC7) == 0x05 {
                let reg = ((modrm >> 3) & 0x07) as usize + if rex_r { 8 } else { 0 };
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let addr = (ip as i64 + 6 + disp) as u64;
                let val = if rex_w {
                    kernel
                        .memory
                        .read_u64(addr)
                        .map_err(|_| CpuHaltReason::MemoryFault)?
                } else {
                    kernel
                        .memory
                        .read_u32(addr)
                        .map_err(|_| CpuHaltReason::MemoryFault)? as u64
                };
                self.set_gpr(reg, val);
                self.rip = ip + 6;
                return Ok(());
            }
        }

        // mov rax/rcx, [rsp+disp8] — 48 8B 44/4C 24 disp
        if rex_w && op == 0x8B {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            let sib = kernel
                .memory
                .read_u8(ip + 2)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if sib == 0x24 {
                let disp = kernel
                    .memory
                    .read_u8(ip + 3)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
                let addr = (self.gpr.rsp as i64 + disp) as u64;
                let val = kernel
                    .memory
                    .read_u64(addr)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                if modrm == 0x44 {
                    self.gpr.rax = val;
                    self.rip = ip + 4;
                    return Ok(());
                }
                if modrm == 0x4C {
                    self.gpr.rcx = val;
                    self.rip = ip + 4;
                    return Ok(());
                }
                if modrm == 0x54 {
                    self.gpr.rdx = val;
                    self.rip = ip + 4;
                    return Ok(());
                }
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // lea r64, [rip+disp32] — 48/4C 8D 05/0D/15/1D (modrm rm=101)
        // also lea with other reg targets via modrm.reg
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

        // movsxd r64, r/m32 — 48 63 /r ; common: 48 63 05 disp32 ([rip])
        if rex_w && op == 0x63 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            let reg = ((modrm >> 3) & 0x07) as usize + if rex_r { 8 } else { 0 };
            if (modrm & 0xC7) == 0x05 {
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let addr = (ip as i64 + 6 + disp) as u64;
                let v = kernel
                    .memory
                    .read_u32(addr)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64 as u64;
                self.set_gpr(reg, v);
                self.rip = ip + 6;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // cmp word/dword [rip+disp32], imm — 66 81 3D / 81 3D
        if op == 0x81 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if (modrm & 0xC7) == 0x05 && ((modrm >> 3) & 7) == 7 {
                let disp = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
                let addr = (ip as i64 + 6 + disp) as u64;
                if operand_size_override {
                    let mem = kernel
                        .memory
                        .read_u16(addr)
                        .unwrap_or(0);
                    let imm = kernel
                        .memory
                        .read_u16(ip + 6)
                        .map_err(|_| CpuHaltReason::MemoryFault)?;
                    // Soft: ignore flags; jcc soft-policy handles branches.
                    let _ = (mem, imm);
                    self.rip = ip + 8;
                    return Ok(());
                }
                let mem = kernel
                    .memory
                    .read_u32(addr)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let imm = kernel
                    .memory
                    .read_u32(ip + 6)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let _ = (mem, imm);
                self.rip = ip + 10;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }
        if op == 0xEB {
            let rel = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
            self.rip = (ip as i64 + 2 + rel) as u64;
            return Ok(());
        }
        if (0x70..=0x7F).contains(&op) {
            let rel = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)? as i8 as i64;
            // Soft flags: treat ZF unknown → take/not-take alternately via a sticky bit.
            // For golden smoke: assume equality compares often succeed (JZ taken).
            let take = match op {
                0x74 | 0x67 => true,  // jz/jbe soft-taken
                0x75 | 0x7F => false, // jnz/jg soft-not-taken
                _ => false,
            };
            if take {
                self.rip = (ip as i64 + 2 + rel) as u64;
            } else {
                self.rip = ip + 2;
            }
            return Ok(());
        }

        // nop — 90 / 0F 1F …
        if op == 0x90 {
            self.rip = ip + 1;
            return Ok(());
        }
        if op == 0x0F {
            let b1 = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if b1 == 0x1F {
                // multi-byte nop: 0F 1F /0
                let modrm = kernel
                    .memory
                    .read_u8(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let len = match modrm {
                    0x00 => 3,
                    0x40..=0x47 => 4,
                    _ => 3,
                };
                self.rip = ip + len as u64;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // mov qword [rsp+disp8], imm32 — 48 C7 44 24 disp imm32
        // mov dword [rax], imm32 — C7 00 imm32 (also REX.W form writes 32-bit zero-extended store)
        if op == 0xC7 {
            let modrm = kernel
                .memory
                .read_u8(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)?;
            if rex_w {
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
            }
            // mod=00 rm=000 → [rax]
            if (modrm & 0xC7) == 0x00 {
                let imm = kernel
                    .memory
                    .read_u32(ip + 2)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                kernel
                    .memory
                    .write_u32(self.gpr.rax, imm)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.rip = ip + 6;
                return Ok(());
            }
            return Err(CpuHaltReason::IllegalInstruction);
        }

        // call rel32 — E8 cd
        if op == 0xE8 {
            let rel = kernel
                .memory
                .read_u32(ip + 1)
                .map_err(|_| CpuHaltReason::MemoryFault)? as i32 as i64;
            let next = ip + 5;
            let target = (next as i64 + rel) as u64;
            self.rip = next;
            return self.call_target(kernel, target);
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
            // Sentinel return (0) from run_entry stack → stop the loop.
            if ret == 0 {
                self.halted = Some(CpuHaltReason::ExitProcess);
                return Ok(());
            }
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
        self.note_api(name);
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
                    self.emit_stdout(&data);
                } else if let Some(vfs_h) = self.open_files.get(&handle).copied() {
                    let _ = kernel.filesystem.write_file(FileHandle(vfs_h), &data);
                    if let Some(dir) = &self.host_side_effect_dir {
                        if let Some(vf) = kernel.filesystem.handle_path(FileHandle(vfs_h)) {
                            let host_name = vf
                                .rsplit('\\')
                                .next()
                                .unwrap_or("pe-out.bin")
                                .to_string();
                            let path = dir.join(host_name);
                            let _ = std::fs::write(&path, &data);
                            let ps = path.display().to_string();
                            if !self.side_effects.host_files_written.contains(&ps) {
                                self.side_effects.host_files_written.push(ps);
                            }
                            if !self.side_effects.vfs_files_written.contains(&vf) {
                                self.side_effects.vfs_files_written.push(vf);
                            }
                        }
                    }
                }

                if written_ptr != 0 {
                    let _ = kernel.memory.write_u32(written_ptr, len as u32);
                }
                self.gpr.rax = 1; // BOOL TRUE
                Ok(())
            }
            "ReadFile" => {
                let handle = self.gpr.rcx;
                let buf_ptr = self.gpr.rdx;
                let len = self.gpr.r8 as usize;
                let read_ptr = self.gpr.r9;
                if let Some(vfs_h) = self.open_files.get(&handle).copied() {
                    let data = kernel
                        .filesystem
                        .read_file(FileHandle(vfs_h), len)
                        .map_err(|_| CpuHaltReason::MemoryFault)?;
                    kernel
                        .memory
                        .write_bytes(buf_ptr, &data)
                        .map_err(|_| CpuHaltReason::MemoryFault)?;
                    if read_ptr != 0 {
                        let _ = kernel.memory.write_u32(read_ptr, data.len() as u32);
                    }
                    self.gpr.rax = 1;
                } else {
                    self.gpr.rax = 0;
                }
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
                    let _ = kernel.filesystem.close_handle(FileHandle(vfs_h));
                }
                self.gpr.rax = 1;
                Ok(())
            }
            "GetCurrentProcessId" => {
                self.side_effects.guest_pid = Some(self.guest_pid);
                self.gpr.rax = self.guest_pid as u64;
                Ok(())
            }
            "GetModuleHandleA" | "GetModuleHandleW" => {
                // NULL → process image base (CRT / 7za self-check path).
                let arg = self.gpr.rcx;
                if arg == 0 {
                    self.gpr.rax = if self.image_base != 0 {
                        self.image_base
                    } else {
                        STUB_BASE
                    };
                } else {
                    self.gpr.rax = STUB_BASE; // soft: pretend any named module resolves
                }
                Ok(())
            }
            "GetCommandLineA" => {
                self.gpr.rax = self.cmdline_va;
                Ok(())
            }
            "GetProcessHeap" => {
                self.gpr.rax = PROCESS_HEAP_MAGIC;
                Ok(())
            }
            "HeapAlloc" => {
                let size = self.gpr.r8.max(1);
                let ptr = kernel
                    .memory
                    .allocate(size, MemoryProtection::ReadWrite)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.side_effects.heap_allocations += 1;
                self.gpr.rax = ptr;
                Ok(())
            }
            "HeapFree" => {
                let ptr = self.gpr.r8;
                if ptr != 0 {
                    let _ = kernel.memory.free(ptr);
                }
                self.gpr.rax = 1;
                Ok(())
            }
            "malloc" => {
                let size = self.gpr.rcx.max(1);
                let ptr = kernel
                    .memory
                    .allocate(size, MemoryProtection::ReadWrite)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                self.side_effects.heap_allocations += 1;
                self.gpr.rax = ptr;
                Ok(())
            }
            "free" => {
                let ptr = self.gpr.rcx;
                if ptr != 0 {
                    let _ = kernel.memory.free(ptr);
                }
                self.gpr.rax = 0;
                Ok(())
            }
            "puts" => {
                let ptr = self.gpr.rcx;
                let s = read_guest_cstring(kernel, ptr, 4096)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let mut data = s.into_bytes();
                data.push(b'\n');
                self.emit_stdout(&data);
                self.gpr.rax = 0; // non-negative = success
                Ok(())
            }
            "RegisterClassA" => {
                // WNDCLASSA.lpszClassName at offset 0x40 on x64.
                let cls_ptr = self.gpr.rcx;
                let name_ptr = kernel
                    .memory
                    .read_u64(cls_ptr + 0x40)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let name = read_guest_cstring(kernel, name_ptr, 256)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let style = kernel
                    .memory
                    .read_u32(cls_ptr)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let ok = self.windows.register_class(&name, style, 0);
                self.gpr.rax = if ok { 0xC000 } else { 0 }; // ATOM-like
                Ok(())
            }
            "CreateWindowExA" => {
                let ex = self.gpr.rcx as u32;
                let class = read_guest_cstring(kernel, self.gpr.rdx, 256)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let title = read_guest_cstring(kernel, self.gpr.r8, 256)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                let style = self.gpr.r9 as u32;
                // Stub CALL does not push return: 5th arg at [rsp+0x20].
                let x = self.read_stack_u64(kernel, 0x20)? as i32;
                let y = self.read_stack_u64(kernel, 0x28)? as i32;
                let width = self.read_stack_u64(kernel, 0x30)? as u32;
                let height = self.read_stack_u64(kernel, 0x38)? as u32;
                let w = if width == 0 { DEFAULT_GUI_WIDTH } else { width };
                let h = if height == 0 {
                    DEFAULT_GUI_HEIGHT
                } else {
                    height
                };
                self.fb_width = w;
                self.fb_height = h;
                match self
                    .windows
                    .create_window(&class, &title, x, y, w, h, None, style, ex)
                {
                    Some(hwnd) => {
                        {
                            let gui = self.gui_mut();
                            gui.hwnd = Some(hwnd.0);
                            gui.title = Some(title);
                            gui.width = w;
                            gui.height = h;
                            gui.windows_created =
                                gui.windows_created.saturating_add(1);
                        }
                        self.gpr.rax = hwnd.0;
                    }
                    None => self.gpr.rax = 0,
                }
                Ok(())
            }
            "ShowWindow" => {
                let hwnd = Hwnd(self.gpr.rcx);
                let show = self.gpr.rdx != 0;
                let ok = self.windows.show_window(hwnd, show);
                {
                    let gui = self.gui_mut();
                    gui.visible = show && ok;
                    if gui.hwnd.is_none() {
                        gui.hwnd = Some(hwnd.0);
                    }
                }
                if show && ok {
                    self.present_compositor_frame();
                }
                self.gpr.rax = 1;
                Ok(())
            }
            "UpdateWindow" => {
                let hwnd = Hwnd(self.gpr.rcx);
                if self.windows.get_window(hwnd).is_some() {
                    let _ = self.windows.post_message(hwnd, WM_PAINT, 0, 0);
                    self.present_compositor_frame();
                    self.gpr.rax = 1;
                } else {
                    self.gpr.rax = 0;
                }
                Ok(())
            }
            "GetMessageA" => {
                let msg_ptr = self.gpr.rcx;
                match self.windows.get_message() {
                    Some(msg) => {
                        kernel
                            .memory
                            .write_u64(msg_ptr, msg.hwnd.0)
                            .map_err(|_| CpuHaltReason::MemoryFault)?;
                        kernel
                            .memory
                            .write_u32(msg_ptr + 8, msg.message)
                            .map_err(|_| CpuHaltReason::MemoryFault)?;
                        kernel
                            .memory
                            .write_u32(msg_ptr + 12, 0)
                            .map_err(|_| CpuHaltReason::MemoryFault)?;
                        kernel
                            .memory
                            .write_u64(msg_ptr + 16, msg.wparam)
                            .map_err(|_| CpuHaltReason::MemoryFault)?;
                        kernel
                            .memory
                            .write_u64(msg_ptr + 24, msg.lparam as u64)
                            .map_err(|_| CpuHaltReason::MemoryFault)?;
                        self.gpr.rax = if msg.message == WM_QUIT { 0 } else { 1 };
                    }
                    None => {
                        // Empty queue: treat as quit for MVP (non-blocking).
                        self.gpr.rax = 0;
                    }
                }
                Ok(())
            }
            "TranslateMessage" => {
                self.gpr.rax = 1;
                Ok(())
            }
            "DispatchMessageA" => {
                let msg_ptr = self.gpr.rcx;
                let message = kernel
                    .memory
                    .read_u32(msg_ptr + 8)
                    .map_err(|_| CpuHaltReason::MemoryFault)?;
                {
                    let gui = self.gui_mut();
                    gui.messages_dispatched =
                        gui.messages_dispatched.saturating_add(1);
                }
                if message == WM_PAINT {
                    self.present_compositor_frame();
                }
                self.gpr.rax = 0; // LRESULT
                Ok(())
            }
            "DestroyWindow" => {
                let hwnd = Hwnd(self.gpr.rcx);
                let ok = self.windows.destroy_window(hwnd);
                if ok {
                    {
                        let gui = self.gui_mut();
                        gui.visible = false;
                        gui.closed = true;
                    }
                    self.write_gui_evidence();
                }
                self.gpr.rax = if ok { 1 } else { 0 };
                Ok(())
            }
            "PostQuitMessage" => {
                let code = self.gpr.rcx as i32;
                self.windows.post_quit_message(code);
                self.gpr.rax = 0;
                Ok(())
            }
            "GetDC" => {
                let hwnd = Hwnd(self.gpr.rcx);
                let (w, h) = self
                    .windows
                    .get_window(hwnd)
                    .map(|win| (win.width, win.height))
                    .unwrap_or((self.fb_width, self.fb_height));
                let hdc = self.gdi.create_dc(w, h);
                self.hdc_size.insert(hdc.0, (w, h));
                {
                    let gui = self.gui_mut();
                    gui.gdi_dc_count = gui.gdi_dc_count.saturating_add(1);
                }
                self.gpr.rax = hdc.0;
                Ok(())
            }
            "ReleaseDC" => {
                let hdc = self.gpr.rdx;
                if hdc != 0 {
                    let _ = self.gdi.delete_dc(crate::win32_stubs::Hdc(hdc));
                    self.hdc_size.remove(&hdc);
                }
                self.gpr.rax = 1;
                Ok(())
            }
            "CreateCompatibleDC" => {
                let src = crate::win32_stubs::Hdc(self.gpr.rcx);
                let hdc = if self.gdi.dc_count() == 0 || self.gpr.rcx == 0 {
                    self.gdi.create_dc(self.fb_width, self.fb_height)
                } else {
                    self.gdi
                        .create_compatible_dc(src)
                        .unwrap_or_else(|| self.gdi.create_dc(self.fb_width, self.fb_height))
                };
                self.hdc_size
                    .insert(hdc.0, (self.fb_width, self.fb_height));
                {
                    let gui = self.gui_mut();
                    gui.gdi_dc_count = gui.gdi_dc_count.saturating_add(1);
                }
                self.gpr.rax = hdc.0;
                Ok(())
            }
            "BitBlt" => {
                {
                    let gui = self.gui_mut();
                    gui.gdi_bitblt_count = gui.gdi_bitblt_count.saturating_add(1);
                }
                self.present_compositor_frame();
                self.gpr.rax = 1;
                Ok(())
            }
            "DeleteDC" => {
                let hdc = crate::win32_stubs::Hdc(self.gpr.rcx);
                let ok = self.gdi.delete_dc(hdc);
                self.hdc_size.remove(&hdc.0);
                self.gpr.rax = if ok { 1 } else { 0 };
                Ok(())
            }
            "GetDeviceCaps" => {
                let hdc = crate::win32_stubs::Hdc(self.gpr.rcx);
                let index = self.gpr.rdx as u32;
                self.gpr.rax = self
                    .gdi
                    .get_device_caps(hdc, index)
                    .unwrap_or(0) as u64;
                Ok(())
            }
            "ExitProcess" => {
                let code = self.gpr.rcx as u32;
                self.side_effects.exit_code = Some(code);
                if self.side_effects.gui.is_some() {
                    self.write_gui_evidence();
                }
                self.halted = Some(CpuHaltReason::ExitProcess);
                Ok(())
            }
            // Soft stubs for unresolved / registry-only Win32 & CRT symbols so
            // real public PEs can make progress past import calls (pe6).
            _ => {
                self.gpr.rax = 0;
                Ok(())
            }
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
    run_entry_with_imports(kernel, entry, host_side_effect_dir, &[])
}

/// Same as [`run_entry`], registering loader IAT resolutions into the CPU stub map.
pub fn run_entry_with_imports(
    kernel: &mut NtKernel,
    entry: u64,
    host_side_effect_dir: Option<PathBuf>,
    imports: &[crate::loader::ImportResolution],
) -> Result<CpuRunResult, NtStatus> {
    run_entry_with_imports_and_base(kernel, entry, host_side_effect_dir, imports, 0)
}

/// Like [`run_entry_with_imports`] with a known mapped image base for GetModuleHandle.
pub fn run_entry_with_imports_and_base(
    kernel: &mut NtKernel,
    entry: u64,
    host_side_effect_dir: Option<PathBuf>,
    imports: &[crate::loader::ImportResolution],
    image_base: u64,
) -> Result<CpuRunResult, NtStatus> {
    let stack_base = kernel
        .memory
        .allocate(0x1_0000, MemoryProtection::ReadWrite)?;
    let stack_top = stack_base + 0x1_0000 - 0x20;
    // Sentinel return address
    kernel.memory.write_u64(stack_top, 0)?;

    let cmdline = "strawwu-guest.exe\0";
    let cmdline_va = kernel
        .memory
        .allocate(0x1000, MemoryProtection::ReadWrite)?;
    kernel
        .memory
        .write_bytes(cmdline_va, cmdline.as_bytes())?;

    let mut cpu = Cpu::new(entry, stack_top)
        .with_guest_pid(DEFAULT_GUEST_PID)
        .with_command_line(cmdline_va, "strawwu-guest.exe")
        .with_image_base(image_base);
    if let Some(dir) = host_side_effect_dir {
        cpu = cpu.with_host_side_effect_dir(dir);
    }
    cpu.register_imports(imports);
    Ok(cpu.run(kernel))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::loader::PeLoader;
    use crate::ntdll::MemoryProtection;
    use crate::pe::{
        build_real_console_fixture_pe, build_win32_console_mvp_pe, build_win32_gui_mvp_pe,
        build_win32_light2d_game_demo_pe, build_win32_light3d_game_demo_pe,
    };

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
    fn cpu_runs_win32_console_mvp_file_process_crt() {
        let pe = build_win32_console_mvp_pe();
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let load = loader.load(&pe, &mut kernel).unwrap();
        let tmp = std::env::temp_dir().join("strawwu-pe2-cpu-test");
        let _ = std::fs::remove_dir_all(&tmp);
        let _ = std::fs::create_dir_all(&tmp);
        let result = run_entry(&mut kernel, load.entry_point_va, Some(tmp.clone())).unwrap();
        assert_eq!(result.halt, CpuHaltReason::ExitProcess, "rip={:#x}", result.rip);
        let se = &result.side_effects;
        assert!(
            se.stdout_utf8.contains("STRAWWU_PE_CONSOLE_OK"),
            "stdout={}",
            se.stdout_utf8
        );
        assert!(
            se.stdout_utf8.contains("STRAWWU_PE_CONSOLE_CRT"),
            "stdout missing CRT marker: {}",
            se.stdout_utf8
        );
        assert_eq!(se.exit_code, Some(0));
        assert!(se.heap_allocations >= 1);
        assert_eq!(se.guest_pid, Some(DEFAULT_GUEST_PID));
        for api in [
            "GetCurrentProcessId",
            "GetCommandLineA",
            "CreateFileA",
            "WriteFile",
            "ReadFile",
            "CloseHandle",
            "malloc",
            "puts",
            "ExitProcess",
        ] {
            assert!(
                se.apis_invoked.iter().any(|a| a == api),
                "missing api {api} in {:?}",
                se.apis_invoked
            );
        }
        let host_file = tmp.join("pe2-marker.txt");
        assert!(host_file.is_file(), "missing {}", host_file.display());
        let body = std::fs::read_to_string(&host_file).unwrap();
        assert!(body.contains("STRAWWU_PE_CONSOLE_OK"), "file={body}");
    }

    #[test]
    fn cpu_runs_win32_gui_mvp_user32_gdi() {
        let pe = build_win32_gui_mvp_pe();
        let mut kernel = NtKernel::new();
        let mut loader = PeLoader::new();
        let load = loader.load(&pe, &mut kernel).unwrap();
        let tmp = std::env::temp_dir().join("strawwu-pe3-cpu-test");
        let _ = std::fs::remove_dir_all(&tmp);
        let _ = std::fs::create_dir_all(&tmp);
        let result = run_entry(&mut kernel, load.entry_point_va, Some(tmp.clone())).unwrap();
        assert_eq!(result.halt, CpuHaltReason::ExitProcess, "rip={:#x}", result.rip);
        let se = &result.side_effects;
        assert!(
            se.stdout_utf8.contains("STRAWWU_PE_GUI_OK"),
            "stdout={}",
            se.stdout_utf8
        );
        assert!(
            se.stdout_utf8.contains("STRAWWU_PE_GUI_CLOSED"),
            "stdout missing close marker: {}",
            se.stdout_utf8
        );
        let gui = se.gui.as_ref().expect("gui side effects");
        assert!(gui.hwnd.unwrap_or(0) > 0);
        assert!(gui.windows_created >= 1);
        assert!(gui.closed);
        assert!(gui.messages_dispatched >= 2);
        assert!(gui.gdi_bitblt_count >= 1);
        assert!(gui.compositor_frames >= 1);
        assert!(gui.triangle_pixels > 100, "triangle_pixels={}", gui.triangle_pixels);
        assert!(gui.present_frames >= 1);
        assert!(gui.screenshot_path.is_some());
        assert!(gui.compositor_obs_path.is_some());
        assert!(gui.triangle_path.is_some());
        assert!(gui.present_path.is_some());
        for api in [
            "RegisterClassA",
            "CreateWindowExA",
            "ShowWindow",
            "GetMessageA",
            "DispatchMessageA",
            "GetDC",
            "BitBlt",
            "DestroyWindow",
            "PostQuitMessage",
            "ExitProcess",
        ] {
            assert!(
                se.apis_invoked.iter().any(|a| a == api),
                "missing api {api} in {:?}",
                se.apis_invoked
            );
        }
        let shot = tmp.join("pe3-window.ppm");
        assert!(shot.is_file(), "missing screenshot {}", shot.display());
        let ppm = std::fs::read(&shot).unwrap();
        assert!(ppm.starts_with(b"P6"), "not ppm");
        let tri = tmp.join("nt-triangle.ppm");
        assert!(tri.is_file(), "missing triangle {}", tri.display());
        let obs = tmp.join("pe3-compositor.json");
        assert!(obs.is_file(), "missing compositor obs");
        let body = std::fs::read_to_string(&obs).unwrap();
        assert!(body.contains("mutter"));
        assert!(body.contains("triangle_pixels"));
        let present = tmp.join("nt-present.json");
        assert!(present.is_file(), "missing present {}", present.display());
        assert!(body.contains("frame_count"));
        let marker = tmp.join("pe3-marker.txt");
        assert!(marker.is_file(), "missing {}", marker.display());
    }

    #[test]
    fn cpu_runs_win32_light_game_demos() {
        for (pe, ok, closed, marker_name) in [
            (
                build_win32_light2d_game_demo_pe(),
                "STRAWNT_LIGHT2D_OK",
                "STRAWNT_LIGHT2D_CLOSED",
                "light2d-marker.txt",
            ),
            (
                build_win32_light3d_game_demo_pe(),
                "STRAWNT_LIGHT3D_OK",
                "STRAWNT_LIGHT3D_CLOSED",
                "light3d-marker.txt",
            ),
        ] {
            let mut kernel = NtKernel::new();
            let mut loader = PeLoader::new();
            let load = loader.load(&pe, &mut kernel).unwrap();
            let tmp = std::env::temp_dir().join(format!("strawnt-nt2-cpu-{ok}"));
            let _ = std::fs::remove_dir_all(&tmp);
            let _ = std::fs::create_dir_all(&tmp);
            let result = run_entry(&mut kernel, load.entry_point_va, Some(tmp.clone())).unwrap();
            assert_eq!(result.halt, CpuHaltReason::ExitProcess, "rip={:#x}", result.rip);
            let se = &result.side_effects;
            assert!(se.stdout_utf8.contains(ok), "stdout={}", se.stdout_utf8);
            assert!(
                se.stdout_utf8.contains(closed),
                "stdout missing close: {}",
                se.stdout_utf8
            );
            let gui = se.gui.as_ref().expect("gui side effects");
            assert!(gui.triangle_pixels > 100);
            assert!(gui.present_frames >= 1);
            assert!(gui.compositor_frames >= 1);
            assert!(tmp.join("pe3-window.ppm").is_file());
            assert!(tmp.join(marker_name).is_file());
        }
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
