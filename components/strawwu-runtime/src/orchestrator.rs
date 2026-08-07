use std::collections::HashMap;

use crate::process::ProcessGraph;
use crate::profile::AppProfile;
use crate::session::{ExecutionBackend, SubsystemSession};

#[derive(Debug)]
pub struct RuntimeOrchestrator {
    sessions: HashMap<String, SubsystemSession>,
    process_graph: ProcessGraph,
    default_session_id: Option<String>,
}

impl RuntimeOrchestrator {
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            process_graph: ProcessGraph::new(),
            default_session_id: None,
        }
    }

    pub fn create_session(&mut self, id: impl Into<String>, backend: ExecutionBackend) -> &SubsystemSession {
        let id = id.into();
        let mut session = SubsystemSession::new(&id, backend);
        session.activate();

        if matches!(backend, ExecutionBackend::Wine | ExecutionBackend::Native)
            && self.default_session_id.is_none()
        {
            self.default_session_id = Some(id.clone());
        }

        self.sessions.insert(id.clone(), session);
        self.sessions.get(&id).unwrap()
    }

    pub fn get_session(&self, id: &str) -> Option<&SubsystemSession> {
        self.sessions.get(id)
    }

    pub fn default_session(&self) -> Option<&SubsystemSession> {
        self.default_session_id
            .as_ref()
            .and_then(|id| self.sessions.get(id))
    }

    pub fn launch_app(&mut self, profile: &AppProfile) -> Result<u64, String> {
        profile.validate()?;

        let backend = profile.resolved_backend();
        let session_id = match backend {
            ExecutionBackend::Wine | ExecutionBackend::Native => {
                if let Some(ref id) = self.default_session_id {
                    id.clone()
                } else {
                    let id = "default".to_string();
                    self.create_session(&id, backend);
                    id
                }
            }
            ExecutionBackend::Container | ExecutionBackend::Microvm => {
                let id = format!("isolated-{}", profile.app_id);
                self.create_session(&id, backend);
                id
            }
        };

        let pid = self.process_graph.spawn(
            &profile.app_id,
            None,
            profile.cooperation.group.clone(),
        );

        if let Some(session) = self.sessions.get_mut(&session_id) {
            session.add_process(pid);
        }

        Ok(pid)
    }

    pub fn terminate_app(&mut self, pid: u64) -> bool {
        if !self.process_graph.terminate(pid) {
            return false;
        }
        for session in self.sessions.values_mut() {
            session.remove_process(pid);
        }
        true
    }

    pub fn active_processes(&self) -> usize {
        self.process_graph.active_count()
    }

    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    pub fn process_graph(&self) -> &ProcessGraph {
        &self.process_graph
    }
}

impl Default for RuntimeOrchestrator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orchestrator_launch_native() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("notepad");
        let pid = orch.launch_app(&profile).unwrap();

        assert_eq!(orch.active_processes(), 1);
        assert!(orch.default_session().is_some());
        assert!(orch.default_session().unwrap().process_ids.contains(&pid));
    }

    #[test]
    fn orchestrator_shared_session() {
        let mut orch = RuntimeOrchestrator::new();
        let p1 = AppProfile::default_win32("app1");
        let p2 = AppProfile::default_win32("app2");

        orch.launch_app(&p1).unwrap();
        orch.launch_app(&p2).unwrap();

        assert_eq!(orch.session_count(), 1);
        assert_eq!(orch.active_processes(), 2);
        assert_eq!(orch.default_session().unwrap().process_ids.len(), 2);
    }

    #[test]
    fn orchestrator_isolated_backend() {
        let mut orch = RuntimeOrchestrator::new();
        let mut profile = AppProfile::default_win32("untrusted");
        profile.execution_backend = "container".into();

        orch.launch_app(&profile).unwrap();
        assert_eq!(orch.session_count(), 1);
        assert!(orch.get_session("isolated-untrusted").is_some());
    }

    #[test]
    fn orchestrator_terminate() {
        let mut orch = RuntimeOrchestrator::new();
        let profile = AppProfile::default_win32("temp-app");
        let pid = orch.launch_app(&profile).unwrap();

        assert!(orch.terminate_app(pid));
        assert_eq!(orch.active_processes(), 0);
    }

    #[test]
    fn cooperation_group_shared() {
        let mut orch = RuntimeOrchestrator::new();
        let mut p1 = AppProfile::default_win32("launcher");
        p1.cooperation.group = Some("steam-bundle".into());
        let mut p2 = AppProfile::default_win32("game");
        p2.cooperation.group = Some("steam-bundle".into());

        let pid1 = orch.launch_app(&p1).unwrap();
        let pid2 = orch.launch_app(&p2).unwrap();

        let members = orch.process_graph().cooperation_members("steam-bundle");
        assert_eq!(members.len(), 2);
        assert!(members.contains(&pid1));
        assert!(members.contains(&pid2));
    }
}
