use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IoctlPolicy {
    Allow,
    Deny,
    Stub,
    Audit,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IoctlRule {
    pub device_path: String,
    pub ioctl_code: u32,
    pub policy: IoctlPolicy,
    pub response: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IoctlResult {
    pub policy: IoctlPolicy,
    pub response: Option<Vec<u8>>,
    pub audit_recorded: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IoctlAuditEntry {
    pub timestamp_ms: u64,
    pub device_path: String,
    pub ioctl_code: u32,
    pub decision: IoctlPolicy,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct IoctlHandler {
    rules: Vec<IoctlRule>,
    audit_log: Vec<IoctlAuditEntry>,
}

impl IoctlHandler {
    pub fn new() -> Self {
        let mut handler = Self {
            rules: Vec::new(),
            audit_log: Vec::new(),
        };
        handler.load_defaults();
        handler
    }

    fn load_defaults(&mut self) {
        self.rules.push(IoctlRule {
            device_path: r"\\.\EasyAntiCheat".into(),
            ioctl_code: 0x2200_0004,
            policy: IoctlPolicy::Stub,
            response: Some(vec![0x01, 0x00, 0x00, 0x00]),
        });
        self.rules.push(IoctlRule {
            device_path: r"\\.\BattlEye".into(),
            ioctl_code: 0x2200_0008,
            policy: IoctlPolicy::Stub,
            response: Some(vec![0x01, 0x00]),
        });
        self.rules.push(IoctlRule {
            device_path: r"\\.\PhysicalDrive0".into(),
            ioctl_code: 0x0007_0000, // IOCTL_DISK_GET_DRIVE_GEOMETRY
            policy: IoctlPolicy::Allow,
            response: None,
        });
        self.rules.push(IoctlRule {
            device_path: r"\\.\Npcap".into(),
            ioctl_code: 0x0000_0000,
            policy: IoctlPolicy::Deny,
            response: None,
        });
    }

    pub fn evaluate(&self, device_path: &str, ioctl_code: u32) -> (IoctlPolicy, Option<&[u8]>) {
        for rule in &self.rules {
            if rule.device_path == device_path && rule.ioctl_code == ioctl_code {
                return (rule.policy, rule.response.as_deref());
            }
        }
        (IoctlPolicy::Audit, None)
    }

    pub fn evaluate_with_audit(&mut self, device_path: &str, ioctl_code: u32) -> IoctlResult {
        let mut policy = IoctlPolicy::Audit;
        let mut response_owned: Option<Vec<u8>> = None;

        for rule in &self.rules {
            if rule.device_path == device_path && rule.ioctl_code == ioctl_code {
                policy = rule.policy;
                response_owned = rule.response.clone();
                break;
            }
        }

        let should_audit = policy == IoctlPolicy::Audit || policy == IoctlPolicy::Deny;

        if should_audit {
            self.audit_log.push(IoctlAuditEntry {
                timestamp_ms: self.audit_log.len() as u64,
                device_path: device_path.to_string(),
                ioctl_code,
                decision: policy,
            });
        }

        IoctlResult {
            policy,
            response: response_owned,
            audit_recorded: should_audit,
        }
    }

    pub fn get_audit_log(&self) -> &[IoctlAuditEntry] {
        &self.audit_log
    }

    pub fn add_rule(&mut self, rule: IoctlRule) {
        self.rules.push(rule);
    }

    pub fn add_rule_batch(&mut self, rules: Vec<IoctlRule>) {
        self.rules.extend(rules);
    }

    pub fn rules_for_device(&self, device_path: &str) -> Vec<&IoctlRule> {
        self.rules
            .iter()
            .filter(|r| r.device_path == device_path)
            .collect()
    }

    pub fn generate_probe_response(device_path: &str, ioctl_code: u32) -> Vec<u8> {
        let mut response = Vec::with_capacity(16);
        response.extend_from_slice(&ioctl_code.to_le_bytes());

        let hash = device_path.bytes().fold(0u32, |acc, b| acc.wrapping_add(b as u32));
        response.extend_from_slice(&hash.to_le_bytes());

        // Pad to 16 bytes with a success pattern
        response.extend_from_slice(&[0x01, 0x00, 0x00, 0x00]);
        response.extend_from_slice(&[0x00; 4]);
        response
    }

    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ioctl_defaults_loaded() {
        let handler = IoctlHandler::new();
        assert!(handler.rule_count() >= 3);
    }

    #[test]
    fn ioctl_eac_stub() {
        let handler = IoctlHandler::new();
        let (policy, resp) = handler.evaluate(r"\\.\EasyAntiCheat", 0x2200_0004);
        assert_eq!(policy, IoctlPolicy::Stub);
        assert!(resp.is_some());
    }

    #[test]
    fn ioctl_npcap_denied() {
        let handler = IoctlHandler::new();
        let (policy, _) = handler.evaluate(r"\\.\Npcap", 0x0000_0000);
        assert_eq!(policy, IoctlPolicy::Deny);
    }

    #[test]
    fn ioctl_unknown_audited() {
        let handler = IoctlHandler::new();
        let (policy, _) = handler.evaluate(r"\\.\UnknownDevice", 0xFFFF_FFFF);
        assert_eq!(policy, IoctlPolicy::Audit);
    }

    #[test]
    fn ioctl_disk_allowed() {
        let handler = IoctlHandler::new();
        let (policy, _) = handler.evaluate(r"\\.\PhysicalDrive0", 0x0007_0000);
        assert_eq!(policy, IoctlPolicy::Allow);
    }

    #[test]
    fn evaluate_with_audit_records_unknown() {
        let mut handler = IoctlHandler::new();
        let result = handler.evaluate_with_audit(r"\\.\SomeDevice", 0xDEAD);
        assert_eq!(result.policy, IoctlPolicy::Audit);
        assert!(result.audit_recorded);
        assert_eq!(handler.get_audit_log().len(), 1);
        assert_eq!(handler.get_audit_log()[0].ioctl_code, 0xDEAD);
    }

    #[test]
    fn evaluate_with_audit_deny_recorded() {
        let mut handler = IoctlHandler::new();
        let result = handler.evaluate_with_audit(r"\\.\Npcap", 0x0000_0000);
        assert_eq!(result.policy, IoctlPolicy::Deny);
        assert!(result.audit_recorded);
        assert_eq!(handler.get_audit_log().len(), 1);
    }

    #[test]
    fn evaluate_with_audit_stub_not_recorded() {
        let mut handler = IoctlHandler::new();
        let result = handler.evaluate_with_audit(r"\\.\EasyAntiCheat", 0x2200_0004);
        assert_eq!(result.policy, IoctlPolicy::Stub);
        assert!(!result.audit_recorded);
        assert!(handler.get_audit_log().is_empty());
    }

    #[test]
    fn add_rule_batch() {
        let mut handler = IoctlHandler::new();
        let initial = handler.rule_count();
        handler.add_rule_batch(vec![
            IoctlRule {
                device_path: r"\\.\DevA".into(),
                ioctl_code: 0x01,
                policy: IoctlPolicy::Allow,
                response: None,
            },
            IoctlRule {
                device_path: r"\\.\DevB".into(),
                ioctl_code: 0x02,
                policy: IoctlPolicy::Deny,
                response: None,
            },
        ]);
        assert_eq!(handler.rule_count(), initial + 2);
    }

    #[test]
    fn rules_for_device_filters() {
        let handler = IoctlHandler::new();
        let eac_rules = handler.rules_for_device(r"\\.\EasyAntiCheat");
        assert_eq!(eac_rules.len(), 1);
        assert_eq!(eac_rules[0].ioctl_code, 0x2200_0004);

        let none_rules = handler.rules_for_device(r"\\.\NoSuch");
        assert!(none_rules.is_empty());
    }

    #[test]
    fn generate_probe_response_deterministic() {
        let resp1 = IoctlHandler::generate_probe_response(r"\\.\EasyAntiCheat", 0x2200_0004);
        let resp2 = IoctlHandler::generate_probe_response(r"\\.\EasyAntiCheat", 0x2200_0004);
        assert_eq!(resp1, resp2);
        assert_eq!(resp1.len(), 16);
        assert_eq!(&resp1[..4], &0x2200_0004u32.to_le_bytes());

        let resp3 = IoctlHandler::generate_probe_response(r"\\.\BattlEye", 0x2200_0004);
        assert_ne!(resp1, resp3);
    }
}
