use serde::{Deserialize, Serialize};

use crate::devices::{self, DeviceStatus};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceMatrix {
    pub matrix_version: String,
    pub devices: Vec<DeviceMatrixEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceMatrixEntry {
    pub class: String,
    pub win32_path: String,
    pub linux_path: String,
    pub tier: String,
    pub status: DeviceStatus,
    pub notes: String,
}

impl DeviceMatrix {
    pub fn generate() -> Self {
        let device_map = devices::default_device_map();
        let entries = device_map.into_iter().map(|d| DeviceMatrixEntry {
            class: d.class.as_str().to_string(),
            win32_path: d.win32_path,
            linux_path: d.linux_path,
            tier: format!("Tier{}", match d.tier {
                devices::ProxyTier::Tier1 => 1,
                devices::ProxyTier::Tier2 => 2,
                devices::ProxyTier::Tier3 => 3,
                devices::ProxyTier::Tier4 => 4,
            }),
            status: d.status,
            notes: d.notes,
        }).collect();

        Self {
            matrix_version: "1".into(),
            devices: entries,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_matrix_generate() {
        let matrix = DeviceMatrix::generate();
        assert_eq!(matrix.matrix_version, "1");
        assert!(!matrix.devices.is_empty());
    }

    #[test]
    fn device_matrix_json() {
        let matrix = DeviceMatrix::generate();
        let json = matrix.to_json();
        assert!(json.contains("matrix_version"));
        assert!(json.contains("GPU"));
        assert!(json.contains("Audio"));
    }

    #[test]
    fn device_matrix_honest() {
        let matrix = DeviceMatrix::generate();
        for entry in &matrix.devices {
            assert!(
                entry.status == DeviceStatus::Partial || entry.status == DeviceStatus::Fail,
                "v3.0 should not claim PASS for device: {}", entry.class
            );
        }
    }
}
