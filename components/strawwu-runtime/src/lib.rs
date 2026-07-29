pub mod session;
pub mod process;
pub mod profile;
pub mod orchestrator;
pub mod executor;
pub mod gui_smoke;
pub mod golden_apps;

pub use session::SubsystemSession;
pub use process::{ProcessGraph, ProcessNode};
pub use profile::AppProfile;
pub use orchestrator::RuntimeOrchestrator;
pub use executor::{
    execute_cooperative, execute_pe, execute_pe_with_side_effect_dir, ExecResult, ExecState,
    ExecutionContext,
};
pub use gui_smoke::{run_gui_smoke, maybe_run_gui_smoke, is_gui_pe, GuiSmokeResult, GuiSmokeState};
pub use golden_apps::{
    default_manifest, generate_golden_apps_report, load_manifest_from_json, report_to_json,
    GoldenAppsManifest, GoldenAppsReport,
};
