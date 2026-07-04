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
}
