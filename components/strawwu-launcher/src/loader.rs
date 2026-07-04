use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::detect::BinaryFormat;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchRequest {
    pub binary_path: PathBuf,
    pub args: Vec<String>,
    pub working_dir: Option<PathBuf>,
    pub format: String,
    pub backend_override: Option<String>,
    pub bundle: Vec<PathBuf>,
    pub profile_path: Option<PathBuf>,
}

impl LaunchRequest {
    pub fn new(binary_path: PathBuf, format: BinaryFormat) -> Self {
        Self {
            binary_path,
            args: Vec::new(),
            working_dir: None,
            format: format.as_str().to_string(),
            backend_override: None,
            bundle: Vec::new(),
            profile_path: None,
        }
    }

    pub fn with_args(mut self, args: Vec<String>) -> Self {
        self.args = args;
        self
    }

    pub fn with_backend(mut self, backend: &str) -> Self {
        self.backend_override = Some(backend.to_string());
        self
    }

    pub fn with_bundle(mut self, paths: Vec<PathBuf>) -> Self {
        self.bundle = paths;
        self
    }

    pub fn is_bundle(&self) -> bool {
        !self.bundle.is_empty()
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.format == "unknown" {
            return Err("cannot launch unknown binary format".into());
        }
        if let Some(ref backend) = self.backend_override {
            if !["native", "container", "microvm"].contains(&backend.as_str()) {
                return Err(format!("invalid backend override: {backend}"));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LaunchResult {
    Started(u64),
    FormatError,
    PolicyDenied,
    SessionUnavailable,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_request_basic() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE);
        assert_eq!(req.format, "PE");
        assert!(!req.is_bundle());
        assert!(req.validate().is_ok());
    }

    #[test]
    fn launch_request_with_bundle() {
        let req = LaunchRequest::new(PathBuf::from("/app/launcher.exe"), BinaryFormat::PE)
            .with_bundle(vec![
                PathBuf::from("/app/launcher.exe"),
                PathBuf::from("/app/game.exe"),
            ]);
        assert!(req.is_bundle());
        assert_eq!(req.bundle.len(), 2);
    }

    #[test]
    fn unknown_format_rejected() {
        let req = LaunchRequest::new(PathBuf::from("/bad/file"), BinaryFormat::Unknown);
        assert!(req.validate().is_err());
    }

    #[test]
    fn invalid_backend_rejected() {
        let req = LaunchRequest::new(PathBuf::from("/app/x.exe"), BinaryFormat::PE)
            .with_backend("winbox");
        assert!(req.validate().is_err());
    }
}
