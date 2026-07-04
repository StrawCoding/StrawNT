use serde::{Deserialize, Serialize};

use strawwu_nt::ntdll::NtKernel;
use strawwu_nt::ipc::PipeNamespace;
use strawwu_nt::loader::{LoadResult, PeLoader};
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

/// Execute a PE binary within the StrawWU runtime.
/// This is the core `strawwu run` flow:
///   1. Parse app profile → determine backend
///   2. Join or create session via orchestrator
///   3. Parse PE binary, map sections, resolve imports
///   4. Build PEB/TEB for the process
///   5. Register IPC pipes in the session namespace
///   6. Transition to Running state
pub fn execute_pe(
    orchestrator: &mut RuntimeOrchestrator,
    profile: &AppProfile,
    pe_data: &[u8],
) -> ExecResult {
    let mut ctx = ExecutionContext::new();

    // Validate profile
    if let Err(e) = profile.validate() {
        return ExecResult {
            pid: 0,
            session_id: String::new(),
            state: ExecState::Failed,
            load_result: None,
            error: Some(e),
        };
    }

    // Launch app in orchestrator (creates/joins session)
    let pid = match orchestrator.launch_app(profile) {
        Ok(pid) => pid,
        Err(e) => {
            return ExecResult {
                pid: 0,
                session_id: String::new(),
                state: ExecState::Failed,
                load_result: None,
                error: Some(e),
            };
        }
    };
    ctx.pid = pid;

    // Determine session
    let backend = profile.resolved_backend();
    let session_id = match backend {
        ExecutionBackend::Native => "default".to_string(),
        ExecutionBackend::Container | ExecutionBackend::Microvm => {
            format!("isolated-{}", profile.app_id)
        }
    };
    ctx.session_id = session_id.clone();
    ctx.state = ExecState::SessionJoined;

    // Load PE
    let load_result = match ctx.loader.load(pe_data, &mut ctx.kernel) {
        Ok(result) => result,
        Err(_status) => {
            return ExecResult {
                pid,
                session_id,
                state: ExecState::Failed,
                load_result: None,
                error: Some("PE loading failed".into()),
            };
        }
    };
    ctx.state = ExecState::PeLoaded;

    // Build PEB and TEB
    let peb = ctx.loader.build_peb(pid, &session_id);
    let teb = ctx.loader.build_teb(1, pid);
    ctx.peb = Some(peb);
    ctx.teb = Some(teb);

    // Register session IPC pipe
    let pipe_name = format!(r"\\.\pipe\strawwu-session-{}", session_id);
    let _ = ctx.pipe_namespace.create_pipe(
        &pipe_name,
        strawwu_nt::ipc::PipeDirection::Duplex,
        pid,
    );

    ctx.state = ExecState::Running;

    ExecResult {
        pid,
        session_id,
        state: ExecState::Running,
        load_result: Some(load_result),
        error: None,
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
    use strawwu_nt::pe::{build_pe_with_imports, build_stub_pe, PeMachine, PeSubsystem};

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

    #[test]
    fn execute_cooperative_apps() {
        let mut orch = RuntimeOrchestrator::new();
        let pe1 = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let pe2 = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsCui);

        let mut p1 = AppProfile::default_win32("launcher");
        p1.cooperation.group = Some("steam-bundle".into());
        let mut p2 = AppProfile::default_win32("game");
        p2.cooperation.group = Some("steam-bundle".into());

        let results = execute_cooperative(&mut orch, &[
            (p1, pe1),
            (p2, pe2),
        ]);

        assert_eq!(results.len(), 2);
        assert!(results.iter().all(|r| r.state == ExecState::Running));
        assert_eq!(results[0].session_id, results[1].session_id);
    }

    #[test]
    fn execute_32bit_pe_wow64() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("legacy32");
        let pe_data = build_pe_with_imports(
            PeMachine::I386,
            PeSubsystem::WindowsGui,
            &[("kernel32.dll", &["GetLastError"])],
        );

        let result = execute_pe(&mut orch, &profile, &pe_data);
        assert_eq!(result.state, ExecState::Running);
    }
}
