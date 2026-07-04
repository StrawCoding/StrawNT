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

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SessionRegistry {
    sessions: HashMap<String, SubsystemSession>,
    next_session_id: u64,
}

impl SessionRegistry {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            next_session_id: 1,
        }
    }

    pub fn register(&mut self, session: SubsystemSession) {
        self.sessions.insert(session.id.clone(), session);
    }

    pub fn get(&self, id: &str) -> Option<&SubsystemSession> {
        self.sessions.get(id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut SubsystemSession> {
        self.sessions.get_mut(id)
    }

    pub fn get_or_create_default(&mut self) -> &mut SubsystemSession {
        let default_id = "default".to_string();
        if !self.sessions.contains_key(&default_id) {
            let mut sess = SubsystemSession::new("default", ExecutionBackend::Native);
            sess.activate();
            self.sessions.insert(default_id.clone(), sess);
        }
        self.sessions.get_mut(&default_id).unwrap()
    }

    pub fn isolate_session(&mut self, app_id: &str, backend: ExecutionBackend) -> String {
        let id = format!("iso-{}-{}", app_id, self.next_session_id);
        self.next_session_id += 1;
        let mut sess = SubsystemSession::new(&id, backend);
        sess.activate();
        self.sessions.insert(id.clone(), sess);
        id
    }

    pub fn session_for_pid(&self, pid: u64) -> Option<&SubsystemSession> {
        self.sessions.values().find(|s| s.process_ids.contains(&pid))
    }

    pub fn cleanup_idle_sessions(&mut self) -> usize {
        let idle_ids: Vec<String> = self
            .sessions
            .iter()
            .filter(|(_, s)| s.process_ids.is_empty() && s.state == SessionState::Idle)
            .map(|(id, _)| id.clone())
            .collect();
        let count = idle_ids.len();
        for id in idle_ids {
            self.sessions.remove(&id);
        }
        count
    }

    pub fn count(&self) -> usize {
        self.sessions.len()
    }

    pub fn all_sessions(&self) -> Vec<&SubsystemSession> {
        self.sessions.values().collect()
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

    #[test]
    fn registry_get_or_create_default() {
        let mut reg = SessionRegistry::new();
        assert_eq!(reg.count(), 0);

        let sess = reg.get_or_create_default();
        assert_eq!(sess.id, "default");
        assert_eq!(sess.state, SessionState::Active);

        sess.add_process(500);
        let sess2 = reg.get_or_create_default();
        assert!(sess2.process_ids.contains(&500));
    }

    #[test]
    fn registry_isolate_session() {
        let mut reg = SessionRegistry::new();
        let id1 = reg.isolate_session("game-a", ExecutionBackend::Container);
        let id2 = reg.isolate_session("game-a", ExecutionBackend::Microvm);

        assert_ne!(id1, id2);
        assert!(id1.contains("game-a"));
        assert_eq!(reg.count(), 2);

        let s1 = reg.get(&id1).unwrap();
        assert_eq!(s1.backend, ExecutionBackend::Container);
        assert_eq!(s1.state, SessionState::Active);
    }

    #[test]
    fn registry_session_for_pid() {
        let mut reg = SessionRegistry::new();
        let id = reg.isolate_session("app", ExecutionBackend::Native);
        reg.get_mut(&id).unwrap().add_process(42);

        let found = reg.session_for_pid(42);
        assert!(found.is_some());
        assert_eq!(found.unwrap().id, id);

        assert!(reg.session_for_pid(9999).is_none());
    }

    #[test]
    fn registry_cleanup_idle() {
        let mut reg = SessionRegistry::new();
        let id1 = reg.isolate_session("a", ExecutionBackend::Native);
        let id2 = reg.isolate_session("b", ExecutionBackend::Native);

        reg.get_mut(&id1).unwrap().add_process(1);
        reg.get_mut(&id1).unwrap().remove_process(1);
        // id1 is now Idle with no processes

        reg.get_mut(&id2).unwrap().add_process(2);
        // id2 is Active with a process

        let cleaned = reg.cleanup_idle_sessions();
        assert_eq!(cleaned, 1);
        assert!(reg.get(&id1).is_none());
        assert!(reg.get(&id2).is_some());
    }

    #[test]
    fn registry_register_and_get() {
        let mut reg = SessionRegistry::new();
        let sess = SubsystemSession::new("custom-1", ExecutionBackend::Microvm);
        reg.register(sess);

        let retrieved = reg.get("custom-1").unwrap();
        assert_eq!(retrieved.backend, ExecutionBackend::Microvm);
        assert_eq!(reg.count(), 1);
    }
}
