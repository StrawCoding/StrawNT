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

    pub fn suspend(&mut self, pid: u64) -> bool {
        if let Some(node) = self.nodes.get_mut(&pid) {
            if node.state == ProcessState::Running {
                node.state = ProcessState::Suspended;
                return true;
            }
        }
        false
    }

    pub fn resume(&mut self, pid: u64) -> bool {
        if let Some(node) = self.nodes.get_mut(&pid) {
            if node.state == ProcessState::Suspended {
                node.state = ProcessState::Running;
                return true;
            }
        }
        false
    }

    pub fn reparent(&mut self, pid: u64, new_parent: u64) -> bool {
        if pid == new_parent {
            return false;
        }
        let parent_exists = self.nodes.contains_key(&new_parent);
        if let Some(node) = self.nodes.get_mut(&pid) {
            if parent_exists && node.state != ProcessState::Terminated {
                node.parent_pid = Some(new_parent);
                return true;
            }
        }
        false
    }

    pub fn siblings_of(&self, pid: u64) -> Vec<u64> {
        let parent = match self.nodes.get(&pid) {
            Some(node) => node.parent_pid,
            None => return Vec::new(),
        };
        match parent {
            Some(ppid) => self
                .nodes
                .values()
                .filter(|n| {
                    n.parent_pid == Some(ppid)
                        && n.pid != pid
                        && n.state != ProcessState::Terminated
                })
                .map(|n| n.pid)
                .collect(),
            None => Vec::new(),
        }
    }

    pub fn process_tree_depth(&self, pid: u64) -> usize {
        let mut depth = 0;
        let mut current = pid;
        while let Some(node) = self.nodes.get(&current) {
            match node.parent_pid {
                Some(ppid) if ppid != current => {
                    depth += 1;
                    current = ppid;
                }
                _ => break,
            }
        }
        depth
    }

    pub fn find_by_name(&self, name: &str) -> Vec<u64> {
        self.nodes
            .values()
            .filter(|n| n.name == name && n.state != ProcessState::Terminated)
            .map(|n| n.pid)
            .collect()
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

    #[test]
    fn suspend_and_resume() {
        let mut graph = ProcessGraph::new();
        let pid = graph.spawn("app.exe", None, None);

        assert!(graph.suspend(pid));
        assert_eq!(graph.get(pid).unwrap().state, ProcessState::Suspended);
        assert!(!graph.suspend(pid)); // already suspended

        assert!(graph.resume(pid));
        assert_eq!(graph.get(pid).unwrap().state, ProcessState::Running);
        assert!(!graph.resume(pid)); // already running
    }

    #[test]
    fn suspend_terminated_fails() {
        let mut graph = ProcessGraph::new();
        let pid = graph.spawn("app.exe", None, None);
        graph.terminate(pid);
        assert!(!graph.suspend(pid));
    }

    #[test]
    fn reparent_process() {
        let mut graph = ProcessGraph::new();
        let parent1 = graph.spawn("launcher.exe", None, None);
        let parent2 = graph.spawn("steam.exe", None, None);
        let child = graph.spawn("game.exe", Some(parent1), None);

        assert!(graph.reparent(child, parent2));
        assert_eq!(graph.get(child).unwrap().parent_pid, Some(parent2));
        assert!(graph.children_of(parent2).contains(&child));
        assert!(!graph.children_of(parent1).contains(&child));
    }

    #[test]
    fn reparent_self_fails() {
        let mut graph = ProcessGraph::new();
        let pid = graph.spawn("app.exe", None, None);
        assert!(!graph.reparent(pid, pid));
    }

    #[test]
    fn siblings_of_process() {
        let mut graph = ProcessGraph::new();
        let parent = graph.spawn("launcher.exe", None, None);
        let c1 = graph.spawn("game.exe", Some(parent), None);
        let c2 = graph.spawn("overlay.exe", Some(parent), None);
        let c3 = graph.spawn("helper.exe", Some(parent), None);

        let siblings = graph.siblings_of(c1);
        assert_eq!(siblings.len(), 2);
        assert!(siblings.contains(&c2));
        assert!(siblings.contains(&c3));
        assert!(!siblings.contains(&c1));
    }

    #[test]
    fn process_tree_depth_calculation() {
        let mut graph = ProcessGraph::new();
        let root = graph.spawn("root.exe", None, None);
        let mid = graph.spawn("mid.exe", Some(root), None);
        let leaf = graph.spawn("leaf.exe", Some(mid), None);

        assert_eq!(graph.process_tree_depth(root), 0);
        assert_eq!(graph.process_tree_depth(mid), 1);
        assert_eq!(graph.process_tree_depth(leaf), 2);
    }

    #[test]
    fn find_by_name_returns_matches() {
        let mut graph = ProcessGraph::new();
        let p1 = graph.spawn("game.exe", None, None);
        let p2 = graph.spawn("game.exe", None, None);
        graph.spawn("other.exe", None, None);

        let found = graph.find_by_name("game.exe");
        assert_eq!(found.len(), 2);
        assert!(found.contains(&p1));
        assert!(found.contains(&p2));

        assert!(graph.find_by_name("nonexistent.exe").is_empty());
    }
}
