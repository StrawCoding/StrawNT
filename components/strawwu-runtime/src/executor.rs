use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use strawwu_nt::cpu::{CpuHaltReason, ExecSideEffects};
use strawwu_nt::ipc::PipeNamespace;
use strawwu_nt::loader::{LoadResult, PeLoader};
use strawwu_nt::ntdll::NtKernel;
use strawwu_nt::run_entry_with_imports_and_base;
use strawwu_nt::teb::{ProcessEnvironmentBlock, ThreadEnvironmentBlock};

use crate::orchestrator::RuntimeOrchestrator;
use crate::profile::AppProfile;
use crate::session::ExecutionBackend;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExecState {
    Init,
    PeLoaded,
    SessionJoined,
    Running,
    Terminated,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecResult {
    pub pid: u64,
    pub session_id: String,
    pub state: ExecState,
    pub load_result: Option<LoadResult>,
    pub error: Option<String>,
    /// `real` when guest CPU loop produced a halt with side effects; otherwise `simulated`.
    pub mode: String,
    pub cpu_executed: bool,
    pub side_effects: Option<ExecSideEffects>,
    pub halt_reason: Option<String>,
}

#[derive(Debug)]
pub struct ExecutionContext {
    pub kernel: NtKernel,
    pub pipe_namespace: PipeNamespace,
    pub loader: PeLoader,
    pub peb: Option<ProcessEnvironmentBlock>,
    pub teb: Option<ThreadEnvironmentBlock>,
    pub state: ExecState,
    pub pid: u64,
    pub session_id: String,
}

impl ExecutionContext {
    pub fn new() -> Self {
        Self {
            kernel: NtKernel::new(),
            pipe_namespace: PipeNamespace::new(),
            loader: PeLoader::new(),
            peb: None,
            teb: None,
            state: ExecState::Init,
            pid: 0,
            session_id: String::new(),
        }
    }
}

impl Default for ExecutionContext {
    fn default() -> Self {
        Self::new()
    }
}

fn entry_has_code(kernel: &NtKernel, entry: u64) -> bool {
    match kernel.memory.read_bytes(entry, 4) {
        Ok(bytes) => bytes.iter().any(|b| *b != 0),
        Err(_) => false,
    }
}

/// Execute a PE binary within the StrawWU runtime.
/// This is the core `strawwu run` flow:
///   1. Parse app profile → determine backend
///   2. Join or create session via orchestrator
///   3. Parse PE binary, map sections, resolve imports
///   4. Build PEB/TEB for the process
///   5. Register IPC pipes in the session namespace
///   6. When entry has real code, run the native CPU loop (not simulated)
///   7. Transition to Running
pub fn execute_pe(
    orchestrator: &mut RuntimeOrchestrator,
    profile: &AppProfile,
    pe_data: &[u8],
) -> ExecResult {
    execute_pe_with_side_effect_dir(orchestrator, profile, pe_data, None)
}

/// Same as [`execute_pe`], optionally mirroring guest stdout/files into `side_effect_dir`.
pub fn execute_pe_with_side_effect_dir(
    orchestrator: &mut RuntimeOrchestrator,
    profile: &AppProfile,
    pe_data: &[u8],
    side_effect_dir: Option<PathBuf>,
) -> ExecResult {
    let mut ctx = ExecutionContext::new();

    if let Err(e) = profile.validate() {
        return ExecResult {
            pid: 0,
            session_id: String::new(),
            state: ExecState::Failed,
            load_result: None,
            error: Some(e),
            mode: "simulated".into(),
            cpu_executed: false,
            side_effects: None,
            halt_reason: None,
        };
    }

    let pid = match orchestrator.launch_app(profile) {
        Ok(pid) => pid,
        Err(e) => {
            return ExecResult {
                pid: 0,
                session_id: String::new(),
                state: ExecState::Failed,
                load_result: None,
                error: Some(e),
                mode: "simulated".into(),
                cpu_executed: false,
                side_effects: None,
                halt_reason: None,
            };
        }
    };
    ctx.pid = pid;

    let backend = profile.resolved_backend();
    let session_id = match backend {
        ExecutionBackend::Wine | ExecutionBackend::Native => "default".to_string(),
        ExecutionBackend::Container | ExecutionBackend::Microvm => {
            format!("isolated-{}", profile.app_id)
        }
    };
    ctx.session_id = session_id.clone();
    ctx.state = ExecState::SessionJoined;

    let load_result = match ctx.loader.load(pe_data, &mut ctx.kernel) {
        Ok(result) => result,
        Err(_status) => {
            return ExecResult {
                pid,
                session_id,
                state: ExecState::Failed,
                load_result: None,
                error: Some("PE loading failed".into()),
                mode: "simulated".into(),
                cpu_executed: false,
                side_effects: None,
                halt_reason: None,
            };
        }
    };
    ctx.state = ExecState::PeLoaded;

    let peb = ctx.loader.build_peb(pid, &session_id);
    let teb = ctx.loader.build_teb(1, pid);
    ctx.peb = Some(peb);
    ctx.teb = Some(teb);

    let pipe_name = format!(r"\\.\pipe\strawwu-session-{}", session_id);
    let _ = ctx.pipe_namespace.create_pipe(
        &pipe_name,
        strawwu_nt::ipc::PipeDirection::Duplex,
        pid,
    );

    if entry_has_code(&ctx.kernel, load_result.entry_point_va) {
        let imports = ctx.loader.import_resolutions.clone();
        let image_base = load_result.mapped_base;
        match run_entry_with_imports_and_base(
            &mut ctx.kernel,
            load_result.entry_point_va,
            side_effect_dir,
            &imports,
            image_base,
        ) {
            Ok(cpu) => {
                let gui_real = cpu
                    .side_effects
                    .gui
                    .as_ref()
                    .map(|g| g.hwnd.unwrap_or(0) > 0 && g.compositor_frames > 0)
                    .unwrap_or(false);
                let real = matches!(cpu.halt, CpuHaltReason::ExitProcess)
                    && (!cpu.side_effects.stdout.is_empty()
                        || !cpu.side_effects.host_files_written.is_empty()
                        || cpu.side_effects.exit_code.is_some()
                        || gui_real);
                let mode = if real {
                    "real".to_string()
                } else {
                    "simulated".to_string()
                };
                return ExecResult {
                    pid,
                    session_id,
                    state: ExecState::Running,
                    load_result: Some(load_result),
                    error: None,
                    mode,
                    cpu_executed: true,
                    side_effects: Some(cpu.side_effects),
                    halt_reason: Some(format!("{:?}", cpu.halt)),
                };
            }
            Err(_) => {
                return ExecResult {
                    pid,
                    session_id,
                    state: ExecState::Failed,
                    load_result: Some(load_result),
                    error: Some("CPU execution setup failed".into()),
                    mode: "simulated".into(),
                    cpu_executed: false,
                    side_effects: None,
                    halt_reason: None,
                };
            }
        }
    }

    ctx.state = ExecState::Running;

    ExecResult {
        pid,
        session_id,
        state: ExecState::Running,
        load_result: Some(load_result),
        error: None,
        mode: "simulated".into(),
        cpu_executed: false,
        side_effects: None,
        halt_reason: None,
    }
}

/// Execute multiple PE apps in the same shared session (cooperation mode).
pub fn execute_cooperative(
    orchestrator: &mut RuntimeOrchestrator,
    apps: &[(AppProfile, Vec<u8>)],
) -> Vec<ExecResult> {
    apps.iter()
        .map(|(profile, pe_data)| execute_pe(orchestrator, profile, pe_data))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use strawwu_nt::pe::{
        build_pe_with_imports, build_real_console_fixture_pe, build_stub_pe,
        build_win32_console_mvp_pe, build_win32_gui_mvp_pe, PeMachine, PeSubsystem,
    };

    #[test]
    fn execute_basic_pe() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("notepad");
        let pe_data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Running);
        assert!(result.pid > 0);
        assert_eq!(result.session_id, "default");
        assert!(result.error.is_none());
        assert_eq!(result.mode, "simulated");
        assert!(!result.cpu_executed);
    }

    #[test]
    fn execute_real_console_fixture() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("pe1-fixture");
        let pe_data = build_real_console_fixture_pe();
        let tmp = std::env::temp_dir().join("strawwu-pe1-exec-test");
        let _ = std::fs::create_dir_all(&tmp);

        let result =
            execute_pe_with_side_effect_dir(&mut orch, &profile, &pe_data, Some(tmp.clone()));
        assert_eq!(result.state, ExecState::Running);
        assert_eq!(result.mode, "real");
        assert!(result.cpu_executed);
        let se = result.side_effects.expect("side effects");
        assert!(se.stdout_utf8.contains("STRAWWU_PE_REAL_OK"));
        assert_eq!(se.exit_code, Some(0));
        assert!(tmp.join("pe-stdout.txt").is_file());
    }

    #[test]
    fn execute_win32_console_mvp_fixture() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("pe2-console-mvp");
        let pe_data = build_win32_console_mvp_pe();
        let tmp = std::env::temp_dir().join("strawwu-pe2-exec-test");
        let _ = std::fs::remove_dir_all(&tmp);
        let _ = std::fs::create_dir_all(&tmp);

        let result =
            execute_pe_with_side_effect_dir(&mut orch, &profile, &pe_data, Some(tmp.clone()));
        assert_eq!(result.state, ExecState::Running);
        assert_eq!(result.mode, "real");
        assert!(result.cpu_executed);
        let se = result.side_effects.expect("side effects");
        assert!(se.stdout_utf8.contains("STRAWWU_PE_CONSOLE_OK"));
        assert!(se.stdout_utf8.contains("STRAWWU_PE_CONSOLE_CRT"));
        assert!(se.heap_allocations >= 1);
        assert!(tmp.join("pe2-marker.txt").is_file());
        assert!(se.apis_invoked.iter().any(|a| a == "ReadFile"));
        assert!(se.apis_invoked.iter().any(|a| a == "malloc"));
        assert!(se.apis_invoked.iter().any(|a| a == "GetCurrentProcessId"));
    }

    #[test]
    fn execute_win32_gui_mvp_fixture() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("pe3-gui-mvp");
        let pe_data = build_win32_gui_mvp_pe();
        let tmp = std::env::temp_dir().join("strawwu-pe3-exec-test");
        let _ = std::fs::remove_dir_all(&tmp);
        let _ = std::fs::create_dir_all(&tmp);

        let result =
            execute_pe_with_side_effect_dir(&mut orch, &profile, &pe_data, Some(tmp.clone()));
        assert_eq!(result.state, ExecState::Running);
        assert_eq!(result.mode, "real");
        assert!(result.cpu_executed);
        let se = result.side_effects.expect("side effects");
        assert!(se.stdout_utf8.contains("STRAWWU_PE_GUI_OK"));
        assert!(se.stdout_utf8.contains("STRAWWU_PE_GUI_CLOSED"));
        let gui = se.gui.expect("gui");
        assert!(gui.hwnd.unwrap_or(0) > 0);
        assert!(gui.closed);
        assert!(gui.compositor_frames >= 1);
        assert!(gui.triangle_pixels > 100, "triangle_pixels={}", gui.triangle_pixels);
        assert!(gui.present_frames >= 1);
        assert!(tmp.join("pe3-window.ppm").is_file());
        assert!(tmp.join("pe3-compositor.json").is_file());
        assert!(tmp.join("nt-triangle.ppm").is_file());
        assert!(tmp.join("nt-present.json").is_file());
        assert!(tmp.join("pe3-marker.txt").is_file());
        assert!(se.apis_invoked.iter().any(|a| a == "CreateWindowExA"));
        assert!(se.apis_invoked.iter().any(|a| a == "BitBlt"));
        assert!(se.apis_invoked.iter().any(|a| a == "DestroyWindow"));
    }

    #[test]
    fn execute_pe_with_imports_resolves() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("myapp");
        let pe_data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsGui,
            &[
                ("kernel32.dll", &["GetLastError", "ExitProcess"]),
                ("user32.dll", &["MessageBoxW"]),
            ],
        );

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Running);
        let lr = result.load_result.unwrap();
        assert_eq!(lr.total_imports, 3);
        assert!(lr.resolved_imports >= 2);
    }

    #[test]
    fn execute_shared_session() {
        let mut orch = RuntimeOrchestrator::new();
        let p1 = AppProfile::default_win32("app1");
        let p2 = AppProfile::default_win32("app2");
        let pe1 = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let pe2 = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsCui);

        let r1 = execute_pe(&mut orch, &p1, &pe1);
        let r2 = execute_pe(&mut orch, &p2, &pe2);

        assert_eq!(r1.state, ExecState::Running);
        assert_eq!(r2.state, ExecState::Running);
        assert_eq!(r1.session_id, r2.session_id);
        assert_eq!(orch.session_count(), 1);
    }

    #[test]
    fn execute_isolated_backend() {
        let mut orch = RuntimeOrchestrator::new();
        let mut profile = AppProfile::default_win32("isolated-app");
        profile.execution_backend = "container".into();
        let pe_data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Running);
        assert_eq!(result.session_id, "isolated-isolated-app");
    }

    #[test]
    fn execute_invalid_profile_fails() {
        let mut orch = RuntimeOrchestrator::new();
        let mut profile = AppProfile::default_win32("bad");
        profile.execution_backend = "winbox".into();
        let pe_data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Failed);
        assert!(result.error.is_some());
    }

    #[test]
    fn execute_invalid_pe_fails() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("badpe");
        let pe_data = vec![0x00; 32];

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Failed);
    }
}
