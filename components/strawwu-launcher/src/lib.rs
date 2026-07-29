pub mod detect;
pub mod loader;
pub mod cli;
pub mod registry;
pub mod desktop;
pub mod open;
pub mod log;
pub mod pe_loader;
pub mod wine_backend;

pub use detect::{BinaryFormat, detect_format};
pub use loader::LaunchRequest;
