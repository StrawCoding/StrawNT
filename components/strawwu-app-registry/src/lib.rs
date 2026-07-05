pub mod cli;
pub mod desktop;
pub mod entry;
pub mod paths;
pub mod registry;
pub mod validate;

pub use entry::{
    AppEntry, AppKind, AppRegistryFile, AppSource, ExecutionBackend, InstallState,
};
pub use desktop::{find_by_desktop, slug_from_desktop_basename};
pub use paths::{default_log_path, default_registry_path};
pub use registry::{load_registry_file, RegistryError, RegistryStore, RemovePreview};
pub use validate::validate_registry;
