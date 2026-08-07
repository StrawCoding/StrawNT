use serde::{Deserialize, Serialize};

use crate::session::ExecutionBackend;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SessionMode {
    Shared,
    Isolated,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FilesystemScope {
    SessionShared,
    AppOverlay,
    Isolated,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RuntimeKind {
    Win32,
    Linux,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GpuMode {
    Vulkan,
    Opengl,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SyscallProfile {
    Daily,
    Game,
    Anticheat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Permissions {
    pub network: bool,
    pub gpu: bool,
    pub filesystem_scope: FilesystemScope,
    pub ipc_scope: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cooperation {
    pub group: Option<String>,
    pub allow_spawn_children: bool,
    pub inherit_registry: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourcePolicy {
    pub gpu_mode: GpuMode,
    pub syscall_profile: SyscallProfile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppProfile {
    pub schema_version: String,
    pub app_id: String,
    pub runtime_kind: RuntimeKind,
    pub execution_backend: String,
    pub session_mode: SessionMode,
    pub permissions: Permissions,
    pub cooperation: Cooperation,
    pub resource_policy: ResourcePolicy,
}

impl AppProfile {
    pub fn default_win32(app_id: impl Into<String>) -> Self {
        Self {
            schema_version: "0.2".to_string(),
            app_id: app_id.into(),
            runtime_kind: RuntimeKind::Win32,
            execution_backend: "wine".to_string(),
            session_mode: SessionMode::Shared,
            permissions: Permissions {
                network: true,
                gpu: true,
                filesystem_scope: FilesystemScope::SessionShared,
                ipc_scope: "session".to_string(),
            },
            cooperation: Cooperation {
                group: None,
                allow_spawn_children: true,
                inherit_registry: true,
            },
            resource_policy: ResourcePolicy {
                gpu_mode: GpuMode::Vulkan,
                syscall_profile: SyscallProfile::Daily,
            },
        }
    }

    pub fn resolved_backend(&self) -> ExecutionBackend {
        ExecutionBackend::from_str(&self.execution_backend).unwrap_or(ExecutionBackend::Wine)
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.app_id.is_empty() {
            return Err("app_id must not be empty".into());
        }
        if self.schema_version != "0.2" {
            return Err(format!("unsupported schema_version: {}", self.schema_version));
        }
        if ExecutionBackend::from_str(&self.execution_backend).is_none() {
            return Err(format!("invalid execution_backend: {}", self.execution_backend));
        }
        if self.permissions.filesystem_scope == FilesystemScope::Isolated
            && self.execution_backend == "native"
        {
            return Err("isolated filesystem requires container or microvm backend".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_profile_valid() {
        let p = AppProfile::default_win32("test-app");
        assert!(p.validate().is_ok());
        assert_eq!(p.resolved_backend(), ExecutionBackend::Wine);
        assert_eq!(p.session_mode, SessionMode::Shared);
    }

    #[test]
    fn wine_backend_accepted() {
        let mut p = AppProfile::default_win32("wine-app");
        p.execution_backend = "wine".into();
        assert!(p.validate().is_ok());
        assert_eq!(p.resolved_backend(), ExecutionBackend::Wine);
    }

    #[test]
    fn profile_json_roundtrip() {
        let p = AppProfile::default_win32("roundtrip-app");
        let json = serde_json::to_string_pretty(&p).unwrap();
        let restored: AppProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.app_id, "roundtrip-app");
        assert_eq!(restored.runtime_kind, RuntimeKind::Win32);
    }

    #[test]
    fn invalid_backend_rejected() {
        let mut p = AppProfile::default_win32("bad");
        p.execution_backend = "winbox".into();
        assert!(p.validate().is_err());
    }

    #[test]
    fn isolated_on_native_rejected() {
        let mut p = AppProfile::default_win32("bad2");
        p.execution_backend = "native".into();
        p.permissions.filesystem_scope = FilesystemScope::Isolated;
        assert!(p.validate().is_err());
    }

    #[test]
    fn empty_app_id_rejected() {
        let mut p = AppProfile::default_win32("");
        p.app_id = String::new();
        assert!(p.validate().is_err());
    }
}
