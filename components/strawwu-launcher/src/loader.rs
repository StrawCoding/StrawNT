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

    pub fn with_working_dir(mut self, dir: PathBuf) -> Self {
        self.working_dir = Some(dir);
        self
    }

    pub fn with_profile(mut self, path: PathBuf) -> Self {
        self.profile_path = Some(path);
        self
    }

    pub fn estimated_backend(&self) -> &str {
        if let Some(ref b) = self.backend_override {
            return b.as_str();
        }
        match self.format.as_str() {
            "PE" | "MSI" | "ELF" => "native",
            _ => "container",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LaunchStage {
    DetectFormat,
    ValidateProfile,
    CreateSession,
    LoadPE,
    BuildEnvironment,
    Ready,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LaunchPipeline {
    pub stage: LaunchStage,
    pub request: LaunchRequest,
    error: Option<String>,
}

impl LaunchPipeline {
    pub fn new(request: LaunchRequest) -> Self {
        Self {
            stage: LaunchStage::DetectFormat,
            request,
            error: None,
        }
    }

    pub fn advance(&mut self) -> Result<LaunchStage, String> {
        self.stage = match self.stage {
            LaunchStage::DetectFormat => {
                if self.request.format == "unknown" {
                    self.error = Some("unknown binary format".into());
                    LaunchStage::Failed
                } else {
                    LaunchStage::ValidateProfile
                }
            }
            LaunchStage::ValidateProfile => {
                if let Err(e) = self.request.validate() {
                    self.error = Some(e);
                    LaunchStage::Failed
                } else {
                    LaunchStage::CreateSession
                }
            }
            LaunchStage::CreateSession => LaunchStage::LoadPE,
            LaunchStage::LoadPE => LaunchStage::BuildEnvironment,
            LaunchStage::BuildEnvironment => LaunchStage::Ready,
            LaunchStage::Ready => return Err("pipeline already complete".into()),
            LaunchStage::Failed => {
                return Err(self.error.clone().unwrap_or_else(|| "unknown error".into()))
            }
        };
        Ok(self.stage)
    }

    pub fn is_complete(&self) -> bool {
        matches!(self.stage, LaunchStage::Ready | LaunchStage::Failed)
    }

    pub fn error(&self) -> Option<&str> {
        self.error.as_deref()
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

    #[test]
    fn with_working_dir_sets_field() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE)
            .with_working_dir(PathBuf::from("/app"));
        assert_eq!(req.working_dir, Some(PathBuf::from("/app")));
    }

    #[test]
    fn with_profile_sets_field() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE)
            .with_profile(PathBuf::from("/etc/profiles/game.json"));
        assert_eq!(req.profile_path, Some(PathBuf::from("/etc/profiles/game.json")));
    }

    #[test]
    fn estimated_backend_pe_native() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE);
        assert_eq!(req.estimated_backend(), "native");
    }

    #[test]
    fn estimated_backend_override() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE)
            .with_backend("container");
        assert_eq!(req.estimated_backend(), "container");
    }

    #[test]
    fn pipeline_full_success() {
        let req = LaunchRequest::new(PathBuf::from("/app/game.exe"), BinaryFormat::PE);
        let mut pipeline = LaunchPipeline::new(req);
        assert!(!pipeline.is_complete());
        assert_eq!(pipeline.stage, LaunchStage::DetectFormat);

        assert_eq!(pipeline.advance().unwrap(), LaunchStage::ValidateProfile);
        assert_eq!(pipeline.advance().unwrap(), LaunchStage::CreateSession);
        assert_eq!(pipeline.advance().unwrap(), LaunchStage::LoadPE);
        assert_eq!(pipeline.advance().unwrap(), LaunchStage::BuildEnvironment);
        assert_eq!(pipeline.advance().unwrap(), LaunchStage::Ready);
        assert!(pipeline.is_complete());
        assert!(pipeline.advance().is_err());
    }

    #[test]
    fn pipeline_fails_on_unknown_format() {
        let req = LaunchRequest::new(PathBuf::from("/bad/file"), BinaryFormat::Unknown);
        let mut pipeline = LaunchPipeline::new(req);
        let stage = pipeline.advance().unwrap();
        assert_eq!(stage, LaunchStage::Failed);
        assert!(pipeline.is_complete());
        assert!(pipeline.error().is_some());
    }
}
