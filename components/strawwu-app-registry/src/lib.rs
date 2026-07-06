pub mod cli;
pub mod deep_remove;
pub mod desktop;
pub mod entry;
pub mod paths;
pub mod registry;
pub mod scan;
pub mod validate;

pub use entry::{
    AppEntry, AppKind, AppRegistryFile, AppSource, ExecutionBackend, InstallState,
};
pub use desktop::{find_by_desktop, slug_from_desktop_basename};
pub use paths::{default_log_path, default_registry_path};
pub use deep_remove::{
    default_allow_prefixes, is_deletable_path, is_forbidden_system_path, plan_deep_remove,
    DeepRemovePlan, DeepRemoveResult, FlatpakUninstallResult, SkippedPath,
};
pub use registry::{
    load_registry_file, RegistryError, RegistryStore, RemovePreview, ScanRemoveAction,
    ScanRemoveResult, ScanUpsertAction,
};
pub use scan::{scan_apps, ScanOptions, ScannedApp};
pub use validate::validate_registry;
