use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    Starting,
    Active,
    Idle,
    Terminating,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExecutionBackend {
    Native,
    Container,
    Microvm,
}

impl ExecutionBackend {
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "native" => Some(Self::Native),
            "container" => Some(Self::Container),
            "microvm" => Some(Self::Microvm),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Native => "native",
            Self::Container => "container",
            Self::Microvm => "microvm",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubsystemSession {
    pub id: String,
    pub state: SessionState,
    pub backend: ExecutionBackend,
    pub process_ids: Vec<u64>,
    pub shared_resources: SharedResources,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SharedResources {
    pub virtual_c_drive: String,
    pub registry_hklm: HashMap<String, String>,
    pub registry_hkcu: HashMap<String, String>,
    pub ipc_namespace: String,
}

impl SubsystemSession {
    pub fn new(id: impl Into<String>, backend: ExecutionBackend) -> Self {
        let id = id.into();
        let ipc_ns = format!("strawwu-ipc-{}", &id);
        Self {
            id: id.clone(),
            state: SessionState::Starting,
            backend,
            process_ids: Vec::new(),
            shared_resources: SharedResources {
                virtual_c_drive: format!("/run/strawwu/sessions/{id}/c_drive"),
                registry_hklm: HashMap::new(),
                registry_hkcu: HashMap::new(),
                ipc_namespace: ipc_ns,
            },
        }
    }

    pub fn activate(&mut self) {
        self.state = SessionState::Active;
    }

    pub fn add_process(&mut self, pid: u64) {
        self.process_ids.push(pid);
        if self.state == SessionState::Idle {
            self.state = SessionState::Active;
        }
    }

    pub fn remove_process(&mut self, pid: u64) {
        self.process_ids.retain(|&p| p != pid);
        if self.process_ids.is_empty() && self.state == SessionState::Active {
            self.state = SessionState::Idle;
        }
    }

    pub fn is_shared(&self) -> bool {
        self.backend == ExecutionBackend::Native
    }

    pub fn terminate(&mut self) {
        self.state = SessionState::Terminating;
        self.process_ids.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_lifecycle() {
        let mut sess = SubsystemSession::new("test-01", ExecutionBackend::Native);
        assert_eq!(sess.state, SessionState::Starting);
        assert!(sess.is_shared());

        sess.activate();
        assert_eq!(sess.state, SessionState::Active);

        sess.add_process(100);
        sess.add_process(101);
        assert_eq!(sess.process_ids.len(), 2);

        sess.remove_process(100);
        assert_eq!(sess.process_ids.len(), 1);

        sess.remove_process(101);
        assert_eq!(sess.state, SessionState::Idle);
    }

    #[test]
    fn session_terminate() {
        let mut sess = SubsystemSession::new("term-01", ExecutionBackend::Container);
        sess.activate();
        sess.add_process(200);
        sess.terminate();
        assert_eq!(sess.state, SessionState::Terminating);
        assert!(sess.process_ids.is_empty());
    }

    #[test]
    fn shared_resources_path() {
        let sess = SubsystemSession::new("my-session", ExecutionBackend::Native);
        assert!(sess.shared_resources.virtual_c_drive.contains("my-session"));
        assert!(sess.shared_resources.ipc_namespace.contains("my-session"));
    }

    #[test]
    fn backend_str_roundtrip() {
        for b in [ExecutionBackend::Native, ExecutionBackend::Container, ExecutionBackend::Microvm] {
            assert_eq!(ExecutionBackend::from_str(b.as_str()), Some(b));
        }
    }
}
