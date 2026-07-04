use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProcessState {
    Created,
    Running,
    Suspended,
    Terminated,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessNode {
    pub pid: u64,
    pub parent_pid: Option<u64>,
    pub name: String,
    pub state: ProcessState,
    pub cooperation_group: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProcessGraph {
    nodes: HashMap<u64, ProcessNode>,
    next_pid: u64,
}

impl ProcessGraph {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            next_pid: 1000,
        }
    }

    pub fn spawn(
        &mut self,
        name: impl Into<String>,
        parent_pid: Option<u64>,
        cooperation_group: Option<String>,
    ) -> u64 {
        let pid = self.next_pid;
        self.next_pid += 1;

        let coop = cooperation_group.or_else(|| {
            parent_pid.and_then(|ppid| {
                self.nodes.get(&ppid).and_then(|p| p.cooperation_group.clone())
            })
        });

        let node = ProcessNode {
            pid,
            parent_pid,
            name: name.into(),
            state: ProcessState::Running,
            cooperation_group: coop,
        };
        self.nodes.insert(pid, node);
        pid
    }

    pub fn terminate(&mut self, pid: u64) -> bool {
        if let Some(node) = self.nodes.get_mut(&pid) {
            node.state = ProcessState::Terminated;
            true
        } else {
            false
        }
    }

    pub fn get(&self, pid: u64) -> Option<&ProcessNode> {
        self.nodes.get(&pid)
    }

    pub fn children_of(&self, pid: u64) -> Vec<u64> {
        self.nodes
            .values()
            .filter(|n| n.parent_pid == Some(pid) && n.state != ProcessState::Terminated)
            .map(|n| n.pid)
            .collect()
    }

    pub fn cooperation_members(&self, group: &str) -> Vec<u64> {
        self.nodes
            .values()
            .filter(|n| {
                n.cooperation_group.as_deref() == Some(group)
                    && n.state != ProcessState::Terminated
            })
            .map(|n| n.pid)
            .collect()
    }

    pub fn active_count(&self) -> usize {
        self.nodes
            .values()
            .filter(|n| matches!(n.state, ProcessState::Running | ProcessState::Suspended))
            .count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spawn_and_terminate() {
        let mut graph = ProcessGraph::new();
        let pid1 = graph.spawn("app.exe", None, Some("bundle-a".into()));
        let pid2 = graph.spawn("helper.exe", Some(pid1), None);

        assert_eq!(graph.active_count(), 2);
        assert_eq!(
            graph.get(pid2).unwrap().cooperation_group.as_deref(),
            Some("bundle-a")
        );

        graph.terminate(pid1);
        assert_eq!(graph.active_count(), 1);
        assert_eq!(graph.get(pid1).unwrap().state, ProcessState::Terminated);
    }

    #[test]
    fn children_of() {
        let mut graph = ProcessGraph::new();
        let parent = graph.spawn("launcher.exe", None, None);
        let c1 = graph.spawn("game.exe", Some(parent), None);
        let c2 = graph.spawn("overlay.exe", Some(parent), None);
        graph.spawn("unrelated.exe", None, None);

        let children = graph.children_of(parent);
        assert_eq!(children.len(), 2);
        assert!(children.contains(&c1));
        assert!(children.contains(&c2));
    }

    #[test]
    fn cooperation_group_query() {
        let mut graph = ProcessGraph::new();
        graph.spawn("steam.exe", None, Some("steam-bundle".into()));
        graph.spawn("game.exe", None, Some("steam-bundle".into()));
        graph.spawn("other.exe", None, Some("other-group".into()));

        let members = graph.cooperation_members("steam-bundle");
        assert_eq!(members.len(), 2);
    }
}
