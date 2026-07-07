use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};
use strawwu_device_proxy::devices::DeviceClass;
use strawwu_device_proxy::matrix::DeviceMatrix;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ListFormat {
    Text,
    Json,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceListEntry {
    pub class: String,
    pub win32_path: String,
    pub linux_path: String,
    pub tier: String,
    pub status: String,
    pub notes: String,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceListPayload {
    pub schema: String,
    pub devices: Vec<DeviceListEntry>,
    pub tier_summary: std::collections::HashMap<String, usize>,
    pub udev_tags: Vec<String>,
}

fn scan_udev_tty_ports() -> Vec<DeviceListEntry> {
    let mut entries = Vec::new();
    let sysfs = Path::new("/sys/class/tty");
    let Ok(read_dir) = fs::read_dir(sysfs) else {
        return entries;
    };

    for entry in read_dir.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !(name.starts_with("ttyUSB") || name.starts_with("ttyACM")) {
            continue;
        }
        let dev_path = format!("/dev/{name}");
        let com_num = entries.len() + 1;
        entries.push(DeviceListEntry {
            class: DeviceClass::SerialCom.as_str().to_string(),
            win32_path: format!(r"\\.\COM{com_num}"),
            linux_path: dev_path,
            tier: "Tier1".into(),
            status: "PARTIAL".into(),
            notes: "udev ttyUSB/ttyACM".into(),
            source: "udev".into(),
        });
    }
    entries
}

/// Enumerate device-proxy mappings for `strawwu devices list`.
pub fn list_devices(format: ListFormat) -> Result<String, String> {
    let matrix = DeviceMatrix::generate();
    let mut devices: Vec<DeviceListEntry> = matrix
        .devices
        .into_iter()
        .map(|entry| DeviceListEntry {
            class: entry.class,
            win32_path: entry.win32_path,
            linux_path: entry.linux_path,
            tier: entry.tier,
            status: entry.status.as_str().to_string(),
            notes: entry.notes,
            source: "device-proxy".into(),
        })
        .collect();

    for udev_entry in scan_udev_tty_ports() {
        if !devices
            .iter()
            .any(|d| d.linux_path == udev_entry.linux_path)
        {
            devices.push(udev_entry);
        }
    }

    let mut summary = std::collections::HashMap::new();
    for dev in &devices {
        *summary.entry(dev.tier.clone()).or_insert(0) += 1;
    }

    let payload = DeviceListPayload {
        schema: "strawwu-devices-list/v1".into(),
        tier_summary: summary,
        udev_tags: vec![
            "strawwu-com-port".into(),
            "strawwu-hid".into(),
            "strawwu-usb".into(),
        ],
        devices,
    };

    match format {
        ListFormat::Json => serde_json::to_string_pretty(&payload)
            .map_err(|e| format!("json encode failed: {e}")),
        ListFormat::Text => {
            if payload.devices.is_empty() {
                return Ok("strawwu: no devices enumerated".into());
            }
            let mut lines = Vec::with_capacity(payload.devices.len());
            for dev in &payload.devices {
                lines.push(format!(
                    "{}\t{}\t{}\t{}\t{}\t{}",
                    dev.class, dev.win32_path, dev.linux_path, dev.tier, dev.status, dev.source
                ));
            }
            Ok(lines.join("\n"))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn devices_list_text_has_rows() {
        let out = list_devices(ListFormat::Text).expect("devices list");
        assert!(out.contains("Serial/COM"));
        assert!(out.contains("Tier1"));
    }

    #[test]
    fn devices_list_json_schema() {
        let out = list_devices(ListFormat::Json).expect("devices list json");
        let payload: DeviceListPayload = serde_json::from_str(&out).expect("valid json");
        assert_eq!(payload.schema, "strawwu-devices-list/v1");
        assert!(!payload.devices.is_empty());
    }
}
