//! Golden apps launch verification for POST-Q8 compat-matrix.
//!
//! Runs in-process launch probes for Office / Steam / Epic / 三角洲 launcher.
//! Emits honest PARTIAL grades — never claims full production launch or gameplay.

use chrono::Utc;
use serde::{Deserialize, Serialize};

use strawwu_nt::ntdll::{FileAccessMode, NtKernel};
use strawwu_nt::pe::{build_stub_pe, PeMachine, PeSubsystem};
use strawwu_nt::win32_stubs::Win32StubRegistry;

use crate::executor::{execute_pe, ExecState};
use crate::gui_smoke::{run_gui_smoke, GuiSmokeState};
use crate::orchestrator::RuntimeOrchestrator;
use crate::profile::{AppProfile, Cooperation, SessionMode, SyscallProfile};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LaunchScope {
    LaunchAndBasicEdit,
    LauncherOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenAppManifest {
    pub id: String,
    pub name: String,
    pub priority: String,
    pub scope: String,
    pub backend_default: String,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenAppsManifest {
    pub version: String,
    pub locked_at: String,
    pub source: String,
    pub apps: Vec<GoldenAppManifest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchProbe {
    pub probe_name: String,
    pub category: String,
    pub passed: bool,
    pub response: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchEvidence {
    pub verified_at: String,
    pub verification_method: String,
    pub verification_stage: String,
    pub probe_pass: usize,
    pub probe_total: usize,
    pub probes: Vec<LaunchProbe>,
    pub cargo_crate: String,
    pub honest_disclaimer: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenAppCase {
    pub id: String,
    pub name: String,
    pub scope: String,
    pub backend: String,
    pub status: String,
    pub grade: String,
    pub launch_verified: bool,
    pub notes: String,
    pub evidence: LaunchEvidence,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenAppsReport {
    pub schema: String,
    pub project_version: String,
    pub generated_at: String,
    pub manifest_version: String,
    pub cases: Vec<GoldenAppCase>,
    pub overall: String,
}

fn scope_from_str(s: &str) -> LaunchScope {
    match s {
        "launch_and_basic_edit" => LaunchScope::LaunchAndBasicEdit,
        _ => LaunchScope::LauncherOnly,
    }
}

fn profile_for_app(app: &GoldenAppManifest) -> AppProfile {
    let scope = scope_from_str(&app.scope);
    let mut profile = AppProfile::default_win32(&app.id);
    profile.execution_backend = app.backend_default.clone();

    match scope {
        LaunchScope::LaunchAndBasicEdit => {
            profile.resource_policy.syscall_profile = SyscallProfile::Daily;
            profile.resource_policy.gpu_mode = crate::profile::GpuMode::None;
            profile.permissions.network = true;
        }
        LaunchScope::LauncherOnly => {
            profile.cooperation = Cooperation {
                group: Some(format!("{}-bundle", app.id)),
                allow_spawn_children: true,
                inherit_registry: true,
            };
            profile.resource_policy.syscall_profile = SyscallProfile::Game;
            profile.resource_policy.gpu_mode = crate::profile::GpuMode::Vulkan;
            profile.permissions.network = true;
        }
    }

    profile.session_mode = SessionMode::Shared;
    profile
}

fn probe_profile_validate(app: &GoldenAppManifest) -> LaunchProbe {
    let profile = profile_for_app(app);
    match profile.validate() {
        Ok(()) => LaunchProbe {
            probe_name: "profile_validate".into(),
            category: "profile".into(),
            passed: true,
            response: format!("AppProfile valid backend={}", profile.execution_backend),
        },
        Err(e) => LaunchProbe {
            probe_name: "profile_validate".into(),
            category: "profile".into(),
            passed: false,
            response: e,
        },
    }
}

fn probe_pe_execute(app: &GoldenAppManifest) -> LaunchProbe {
    let profile = profile_for_app(app);
    let pe = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
    let mut orch = RuntimeOrchestrator::new();
    let result = execute_pe(&mut orch, &profile, &pe);

    let passed = result.state == ExecState::Running && result.error.is_none();
    LaunchProbe {
        probe_name: "pe_execute".into(),
        category: "runtime".into(),
        passed,
        response: format!(
            "state={:?} pid={} session={}",
            result.state, result.pid, result.session_id
        ),
    }
}

fn probe_gui_smoke(app: &GoldenAppManifest) -> LaunchProbe {
    let title = format!("{} Smoke", app.name);
    match run_gui_smoke(&app.id, &title, 1024, 768) {
        Ok(smoke) => LaunchProbe {
            probe_name: "gui_smoke".into(),
            category: "gui".into(),
            passed: smoke.state == GuiSmokeState::Presented && smoke.visible,
            response: format!(
                "hwnd={} compositor={} frames={}",
                smoke.hwnd, smoke.compositor, smoke.frame_count
            ),
        },
        Err(e) => LaunchProbe {
            probe_name: "gui_smoke".into(),
            category: "gui".into(),
            passed: false,
            response: e,
        },
    }
}

fn probe_com_stub() -> LaunchProbe {
    let reg = Win32StubRegistry::new();
    let co_init = reg.resolve("ole32.dll", "CoInitializeEx");
    let co_create = reg.resolve("ole32.dll", "CoCreateInstance");
    let passed = matches!(co_init, strawwu_nt::ntdll::NtStatus::Success)
        && matches!(co_create, strawwu_nt::ntdll::NtStatus::Success);
    LaunchProbe {
        probe_name: "com_stub".into(),
        category: "office".into(),
        passed,
        response: format!(
            "CoInitializeEx={:?} CoCreateInstance={:?}",
            co_init, co_create
        ),
    }
}

fn probe_vfs_doc_open(app_id: &str) -> LaunchProbe {
    let mut kernel = NtKernel::new();
    let path = format!(r"C:\Users\test\Documents\{app_id}-smoke.docx");
    let write_ok = kernel
        .filesystem
        .create_file(&path, FileAccessMode::ReadWrite)
        .and_then(|h| kernel.filesystem.write_file(h, b"StrawWU golden smoke"))
        .is_ok();
    let read_ok = kernel
        .filesystem
        .open_file(&path, FileAccessMode::Read)
        .and_then(|h| kernel.filesystem.read_file(h, 64))
        .map(|buf| !buf.is_empty())
        .unwrap_or(false);

    LaunchProbe {
        probe_name: "vfs_doc_open".into(),
        category: "office".into(),
        passed: write_ok && read_ok,
        response: format!("write={write_ok} read={read_ok} path={path}"),
    }
}

fn probe_cooperation_group(app: &GoldenAppManifest) -> LaunchProbe {
    let profile = profile_for_app(app);
    let group = profile.cooperation.group.clone().unwrap_or_default();
    let mut orch = RuntimeOrchestrator::new();
    let pid = orch.launch_app(&profile).unwrap_or(0);
    let members = orch.process_graph().cooperation_members(&group);
    let passed = !group.is_empty() && pid > 0 && members.contains(&pid);
    LaunchProbe {
        probe_name: "cooperation_group".into(),
        category: "launcher".into(),
        passed,
        response: format!("group={group} pid={pid} members={members:?}"),
    }
}

fn probe_ipc_pipe(app: &GoldenAppManifest) -> LaunchProbe {
    use strawwu_nt::ipc::{PipeDirection, PipeNamespace};

    let profile = profile_for_app(app);
    let mut pipes = PipeNamespace::new();
    let pipe_name = format!(r"\\.\pipe\{id}-launcher", id = app.id);
    let created = pipes
        .create_pipe(&pipe_name, PipeDirection::Duplex, 1001)
        .is_ok();
    let connected = pipes.connect_pipe(&pipe_name, 1002).is_ok();
    let passed = created && connected && profile.permissions.network;
    LaunchProbe {
        probe_name: "ipc_pipe".into(),
        category: "launcher".into(),
        passed,
        response: format!("pipe={pipe_name} created={created} connected={connected}"),
    }
}

fn probe_launcher_window(app: &GoldenAppManifest) -> LaunchProbe {
    use strawwu_nt::win32_stubs::WindowManager;

    let mut wm = WindowManager::new();
    let class = format!("{}LauncherWnd", app.id.replace('-', ""));
    wm.register_class(&class, 0, 0);
    let title = format!("{} — Login", app.name);
    let hwnd = wm.create_window(&class, &title, 200, 200, 1280, 720, None, 0, 0);
    let shown = hwnd
        .and_then(|h| {
            wm.show_window(h, true);
            wm.get_window(h).map(|w| w.visible)
        })
        .unwrap_or(false);

    LaunchProbe {
        probe_name: "launcher_window".into(),
        category: "launcher".into(),
        passed: shown,
        response: format!("class={class} title={title} visible={shown}"),
    }
}

fn grade_for_scope(scope: LaunchScope, ratio: f64) -> &'static str {
    match scope {
        LaunchScope::LauncherOnly => {
            if ratio >= 0.85 {
                "B"
            } else if ratio >= 0.65 {
                "C"
            } else {
                "F"
            }
        }
        LaunchScope::LaunchAndBasicEdit => {
            if ratio >= 0.8 {
                "C"
            } else if ratio >= 0.5 {
                "C"
            } else {
                "F"
            }
        }
    }
}

fn status_for_ratio(ratio: f64) -> &'static str {
    if ratio >= 0.5 {
        "PARTIAL"
    } else {
        "FAIL"
    }
}

fn run_probes_for_app(app: &GoldenAppManifest) -> Vec<LaunchProbe> {
    let scope = scope_from_str(&app.scope);
    let mut probes = vec![
        probe_profile_validate(app),
        probe_pe_execute(app),
        probe_gui_smoke(app),
    ];

    match scope {
        LaunchScope::LaunchAndBasicEdit => {
            probes.push(probe_com_stub());
            probes.push(probe_vfs_doc_open(&app.id));
        }
        LaunchScope::LauncherOnly => {
            probes.push(probe_cooperation_group(app));
            probes.push(probe_ipc_pipe(app));
            probes.push(probe_launcher_window(app));
        }
    }

    probes
}

fn build_case(app: &GoldenAppManifest) -> GoldenAppCase {
    let scope = scope_from_str(&app.scope);
    let probes = run_probes_for_app(app);
    let pass = probes.iter().filter(|p| p.passed).count();
    let total = probes.len();
    let ratio = if total > 0 {
        pass as f64 / total as f64
    } else {
        0.0
    };

    GoldenAppCase {
        id: app.id.clone(),
        name: app.name.clone(),
        scope: app.scope.clone(),
        backend: app.backend_default.clone(),
        status: status_for_ratio(ratio).into(),
        grade: grade_for_scope(scope, ratio).into(),
        launch_verified: ratio >= 0.5,
        notes: app.notes.clone(),
        evidence: LaunchEvidence {
            verified_at: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
            verification_method: "LaunchProbeEngine (cargo test + in-process simulation)".into(),
            verification_stage: "post-q8-golden-apps".into(),
            probe_pass: pass,
            probe_total: total,
            probes,
            cargo_crate: "strawwu-runtime".into(),
            honest_disclaimer:
                "PARTIAL only — simulated launch probes; no real Office/Steam/Epic/三角洲 binaries"
                    .into(),
        },
    }
}

pub fn default_manifest() -> GoldenAppsManifest {
    GoldenAppsManifest {
        version: "0.7.0.8".into(),
        locked_at: "2026-07-08".into(),
        source: "user Q8 decision".into(),
        apps: vec![
            GoldenAppManifest {
                id: "office".into(),
                name: "Microsoft Office (suite)".into(),
                priority: "P0".into(),
                scope: "launch_and_basic_edit".into(),
                backend_default: "native".into(),
                notes: "Word/Excel 基本開檔與編輯".into(),
            },
            GoldenAppManifest {
                id: "steam-launcher".into(),
                name: "Steam Client".into(),
                priority: "P0".into(),
                scope: "launcher_only".into(),
                backend_default: "native".into(),
                notes: "啟動與登入 UI；不驗遊戲執行".into(),
            },
            GoldenAppManifest {
                id: "epic-launcher".into(),
                name: "Epic Games Launcher".into(),
                priority: "P0".into(),
                scope: "launcher_only".into(),
                backend_default: "native".into(),
                notes: "啟動與登入 UI；不驗遊戲執行".into(),
            },
            GoldenAppManifest {
                id: "delta-force-launcher".into(),
                name: "三角洲行動啟動器".into(),
                priority: "P0".into(),
                scope: "launcher_only".into(),
                backend_default: "native".into(),
                notes: "僅啟動器；不驗遊戲本體與反作弊連線".into(),
            },
        ],
    }
}

pub fn load_manifest_from_json(json: &str) -> Result<GoldenAppsManifest, String> {
    serde_json::from_str(json).map_err(|e| format!("invalid golden-apps manifest: {e}"))
}

pub fn generate_golden_apps_report(
    project_version: &str,
    manifest: &GoldenAppsManifest,
) -> GoldenAppsReport {
    let cases: Vec<GoldenAppCase> = manifest.apps.iter().map(build_case).collect();
    let verified = cases.iter().filter(|c| c.launch_verified).count();

    GoldenAppsReport {
        schema: "strawwu-golden-apps-launch/v1".into(),
        project_version: project_version.into(),
        generated_at: Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        manifest_version: manifest.version.clone(),
        cases,
        overall: if verified == manifest.apps.len() {
            "PARTIAL".into()
        } else {
            "FAIL".into()
        },
    }
}

pub fn report_to_json(report: &GoldenAppsReport) -> String {
    serde_json::to_string_pretty(report).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_has_four_p0_apps() {
        let manifest = default_manifest();
        assert_eq!(manifest.apps.len(), 4);
        assert!(manifest.apps.iter().all(|a| a.priority == "P0"));
    }

    #[test]
    fn golden_report_all_cases_verified() {
        let manifest = default_manifest();
        let report = generate_golden_apps_report("0.7.0.8", &manifest);
        assert_eq!(report.cases.len(), 4);
        assert!(report.cases.iter().all(|c| c.launch_verified));
        assert_eq!(report.overall, "PARTIAL");
    }

    #[test]
    fn never_claims_full_pass() {
        let manifest = default_manifest();
        let report = generate_golden_apps_report("0.7.0.8", &manifest);
        for case in &report.cases {
            assert_ne!(case.status, "PASS");
            assert_ne!(case.grade, "A");
            assert!(case.evidence.honest_disclaimer.contains("PARTIAL"));
        }
    }

    #[test]
    fn launcher_cases_use_launcher_probes() {
        let manifest = default_manifest();
        let report = generate_golden_apps_report("0.7.0.8", &manifest);
        let steam = report.cases.iter().find(|c| c.id == "steam-launcher").unwrap();
        let names: Vec<_> = steam
            .evidence
            .probes
            .iter()
            .map(|p| p.probe_name.as_str())
            .collect();
        assert!(names.contains(&"cooperation_group"));
        assert!(names.contains(&"launcher_window"));
    }

    #[test]
    fn office_case_includes_com_and_vfs() {
        let manifest = default_manifest();
        let report = generate_golden_apps_report("0.7.0.8", &manifest);
        let office = report.cases.iter().find(|c| c.id == "office").unwrap();
        let names: Vec<_> = office
            .evidence
            .probes
            .iter()
            .map(|p| p.probe_name.as_str())
            .collect();
        assert!(names.contains(&"com_stub"));
        assert!(names.contains(&"vfs_doc_open"));
    }

    #[test]
    fn json_roundtrip() {
        let manifest = default_manifest();
        let report = generate_golden_apps_report("0.7.0.8", &manifest);
        let json = report_to_json(&report);
        assert!(json.contains("launch_verified"));
        assert!(json.contains("delta-force-launcher"));
    }
}
