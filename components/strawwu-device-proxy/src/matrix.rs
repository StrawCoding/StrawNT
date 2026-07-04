use std::collections::HashMap;

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

    pub fn tier_summary(&self) -> HashMap<String, usize> {
        let mut counts: HashMap<String, usize> = HashMap::new();
        for entry in &self.devices {
            *counts.entry(entry.tier.clone()).or_insert(0) += 1;
        }
        counts
    }

    pub fn pass_rate(&self) -> f64 {
        if self.devices.is_empty() {
            return 0.0;
        }
        let passed = self
            .devices
            .iter()
            .filter(|d| d.status == DeviceStatus::Pass)
            .count();
        passed as f64 / self.devices.len() as f64
    }

    pub fn get_device(&self, class: &str) -> Option<&DeviceMatrixEntry> {
        self.devices.iter().find(|d| d.class == class)
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

    #[test]
    fn tier_summary_counts() {
        let matrix = DeviceMatrix::generate();
        let summary = matrix.tier_summary();
        assert!(!summary.is_empty());
        let total: usize = summary.values().sum();
        assert_eq!(total, matrix.devices.len());
    }

    #[test]
    fn pass_rate_zero_for_v3() {
        let matrix = DeviceMatrix::generate();
        assert!(
            matrix.pass_rate() < 1.0,
            "v3.0 should not have 100% pass rate"
        );
        assert_eq!(matrix.pass_rate(), 0.0, "v3.0 should have 0% PASS");
    }

    #[test]
    fn get_device_by_class() {
        let matrix = DeviceMatrix::generate();
        let gpu = matrix.get_device("GPU");
        assert!(gpu.is_some());
        assert_eq!(gpu.unwrap().class, "GPU");
        assert!(matrix.get_device("NonExistent").is_none());
    }
}
