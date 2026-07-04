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

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct IoctlHandler {
    rules: Vec<IoctlRule>,
}

impl IoctlHandler {
    pub fn new() -> Self {
        let mut handler = Self { rules: Vec::new() };
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

    pub fn add_rule(&mut self, rule: IoctlRule) {
        self.rules.push(rule);
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
}
