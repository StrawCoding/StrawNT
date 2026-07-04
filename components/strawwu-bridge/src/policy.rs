use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SeccompProfile {
    Daily,
    Game,
    Anticheat,
}

impl SeccompProfile {
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "daily" => Some(Self::Daily),
            "game" => Some(Self::Game),
            "anticheat" => Some(Self::Anticheat),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Daily => "daily",
            Self::Game => "game",
            Self::Anticheat => "anticheat",
        }
    }

    pub fn blocked_syscalls(&self) -> &'static [&'static str] {
        match self {
            Self::Daily => &["ptrace", "process_vm_readv", "process_vm_writev"],
            Self::Game => &["ptrace"],
            Self::Anticheat => &[
                "ptrace",
                "process_vm_readv",
                "process_vm_writev",
                "kexec_load",
                "init_module",
                "finit_module",
            ],
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PolicyDecision {
    Allow,
    Deny,
    Audit,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyRule {
    pub syscall_name: String,
    pub decision: PolicyDecision,
    pub profile: SeccompProfile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicySet {
    pub profile: SeccompProfile,
    pub rules: Vec<PolicyRule>,
}

impl PolicySet {
    pub fn new(profile: SeccompProfile) -> Self {
        let rules = profile
            .blocked_syscalls()
            .iter()
            .map(|&sc| PolicyRule {
                syscall_name: sc.to_string(),
                decision: PolicyDecision::Deny,
                profile,
            })
            .collect();
        Self { profile, rules }
    }

    pub fn evaluate(&self, syscall_name: &str) -> PolicyDecision {
        for rule in &self.rules {
            if rule.syscall_name == syscall_name {
                return rule.decision;
            }
        }
        PolicyDecision::Allow
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub timestamp: u64,
    pub syscall: String,
    pub pid: u64,
    pub session_id: String,
    pub decision: PolicyDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicyEngine {
    policy_sets: Vec<PolicySet>,
    exceptions: Vec<PolicyRule>,
    audit_log: Vec<AuditEntry>,
    next_timestamp: u64,
}

impl PolicyEngine {
    pub fn new() -> Self {
        Self {
            policy_sets: Vec::new(),
            exceptions: Vec::new(),
            audit_log: Vec::new(),
            next_timestamp: 1,
        }
    }

    pub fn add_policy_set(&mut self, ps: PolicySet) {
        self.policy_sets.push(ps);
    }

    pub fn add_exception(&mut self, syscall_name: &str, decision: PolicyDecision) {
        self.exceptions.push(PolicyRule {
            syscall_name: syscall_name.to_string(),
            decision,
            profile: SeccompProfile::Daily,
        });
    }

    pub fn evaluate_with_context(
        &mut self,
        syscall_name: &str,
        pid: u64,
        session_id: &str,
    ) -> PolicyDecision {
        // Exceptions take highest priority
        for exc in &self.exceptions {
            if exc.syscall_name == syscall_name {
                let decision = exc.decision;
                self.record_audit(syscall_name, pid, session_id, decision);
                return decision;
            }
        }

        // Evaluate policy sets in priority order (later additions = higher priority)
        for ps in self.policy_sets.iter().rev() {
            let decision = ps.evaluate(syscall_name);
            if decision != PolicyDecision::Allow {
                self.record_audit(syscall_name, pid, session_id, decision);
                return decision;
            }
        }

        let decision = PolicyDecision::Allow;
        self.record_audit(syscall_name, pid, session_id, decision);
        decision
    }

    pub fn get_audit_log(&self) -> &[AuditEntry] {
        &self.audit_log
    }

    pub fn clear_audit_log(&mut self) {
        self.audit_log.clear();
    }

    fn record_audit(
        &mut self,
        syscall: &str,
        pid: u64,
        session_id: &str,
        decision: PolicyDecision,
    ) {
        let ts = self.next_timestamp;
        self.next_timestamp += 1;
        self.audit_log.push(AuditEntry {
            timestamp: ts,
            syscall: syscall.to_string(),
            pid,
            session_id: session_id.to_string(),
            decision,
        });
    }
}

impl Default for PolicyEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn daily_blocks_ptrace() {
        let ps = PolicySet::new(SeccompProfile::Daily);
        assert_eq!(ps.evaluate("ptrace"), PolicyDecision::Deny);
        assert_eq!(ps.evaluate("read"), PolicyDecision::Allow);
    }

    #[test]
    fn game_allows_process_vm() {
        let ps = PolicySet::new(SeccompProfile::Game);
        assert_eq!(ps.evaluate("process_vm_readv"), PolicyDecision::Allow);
        assert_eq!(ps.evaluate("ptrace"), PolicyDecision::Deny);
    }

    #[test]
    fn anticheat_blocks_modules() {
        let ps = PolicySet::new(SeccompProfile::Anticheat);
        assert_eq!(ps.evaluate("init_module"), PolicyDecision::Deny);
        assert_eq!(ps.evaluate("finit_module"), PolicyDecision::Deny);
    }

    #[test]
    fn profile_roundtrip_str() {
        for p in [SeccompProfile::Daily, SeccompProfile::Game, SeccompProfile::Anticheat] {
            assert_eq!(SeccompProfile::from_str(p.as_str()), Some(p));
        }
    }

    #[test]
    fn engine_combines_policy_sets() {
        let mut engine = PolicyEngine::new();
        engine.add_policy_set(PolicySet::new(SeccompProfile::Daily));
        engine.add_policy_set(PolicySet::new(SeccompProfile::Game));

        let decision = engine.evaluate_with_context("ptrace", 1000, "sess-1");
        assert_eq!(decision, PolicyDecision::Deny);

        let decision = engine.evaluate_with_context("read", 1000, "sess-1");
        assert_eq!(decision, PolicyDecision::Allow);
    }

    #[test]
    fn engine_exception_overrides_policy() {
        let mut engine = PolicyEngine::new();
        engine.add_policy_set(PolicySet::new(SeccompProfile::Daily));
        engine.add_exception("ptrace", PolicyDecision::Allow);

        let decision = engine.evaluate_with_context("ptrace", 1000, "sess-1");
        assert_eq!(decision, PolicyDecision::Allow);
    }

    #[test]
    fn engine_audit_log_records_all() {
        let mut engine = PolicyEngine::new();
        engine.add_policy_set(PolicySet::new(SeccompProfile::Daily));

        engine.evaluate_with_context("read", 100, "s1");
        engine.evaluate_with_context("ptrace", 101, "s1");
        engine.evaluate_with_context("write", 102, "s2");

        let log = engine.get_audit_log();
        assert_eq!(log.len(), 3);
        assert_eq!(log[0].syscall, "read");
        assert_eq!(log[0].pid, 100);
        assert_eq!(log[1].decision, PolicyDecision::Deny);
        assert_eq!(log[2].session_id, "s2");
    }

    #[test]
    fn engine_audit_timestamps_increment() {
        let mut engine = PolicyEngine::new();
        engine.evaluate_with_context("read", 1, "s1");
        engine.evaluate_with_context("write", 2, "s1");

        let log = engine.get_audit_log();
        assert!(log[1].timestamp > log[0].timestamp);
    }

    #[test]
    fn engine_clear_audit_log() {
        let mut engine = PolicyEngine::new();
        engine.evaluate_with_context("read", 1, "s1");
        assert!(!engine.get_audit_log().is_empty());

        engine.clear_audit_log();
        assert!(engine.get_audit_log().is_empty());
    }
}
