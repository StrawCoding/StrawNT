pub mod detect;
pub mod loader;
pub mod cli;
pub mod registry;
pub mod desktop;
pub mod log;
pub mod pe_loader;

pub use detect::{BinaryFormat, detect_format};
pub use loader::LaunchRequest;
