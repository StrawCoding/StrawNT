use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceClass {
    Gpu,
    Audio,
    Keyboard,
    Mouse,
    Gamepad,
    SerialCom,
    Printer,
    UsbHid,
    Network,
    Storage,
}

impl DeviceClass {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Gpu => "GPU",
            Self::Audio => "Audio",
            Self::Keyboard => "Keyboard",
            Self::Mouse => "Mouse",
            Self::Gamepad => "Gamepad",
            Self::SerialCom => "Serial/COM",
            Self::Printer => "Printer",
            Self::UsbHid => "USB HID",
            Self::Network => "Network",
            Self::Storage => "Storage",
        }
    }

    pub fn linux_subsystem(&self) -> &'static str {
        match self {
            Self::Gpu => "drm",
            Self::Audio => "sound",
            Self::Keyboard | Self::Mouse | Self::Gamepad => "input",
            Self::SerialCom => "tty",
            Self::Printer => "usb",
            Self::UsbHid => "hidraw",
            Self::Network => "net",
            Self::Storage => "block",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProxyTier {
    Tier1, // Linux has native driver
    Tier2, // Userspace reimplementation
    Tier3, // Virtual device / probe response
    Tier4, // Hardware passthrough
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceStatus {
    #[serde(rename = "PASS")]
    Pass,
    #[serde(rename = "PARTIAL")]
    Partial,
    #[serde(rename = "FAIL")]
    Fail,
}

impl DeviceStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pass => "PASS",
            Self::Partial => "PARTIAL",
            Self::Fail => "FAIL",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtualDevice {
    pub class: DeviceClass,
    pub win32_path: String,
    pub linux_path: String,
    pub tier: ProxyTier,
    pub status: DeviceStatus,
    pub notes: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HotplugAction {
    Add,
    Remove,
    Change,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HotplugEvent {
    pub class: DeviceClass,
    pub action: HotplugAction,
    pub device_path: String,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum DeviceError {
    #[error("device not found: {0}")]
    NotFound(String),
    #[error("duplicate device path: {0}")]
    Duplicate(String),
    #[error("invalid device class for hotplug")]
    InvalidClass,
}

#[derive(Debug, Clone, Default)]
pub struct DeviceEnumerator {
    devices: Vec<VirtualDevice>,
}

impl DeviceEnumerator {
    pub fn new(devices: Vec<VirtualDevice>) -> Self {
        Self { devices }
    }

    pub fn enumerate_by_class(&self, class: DeviceClass) -> Vec<&VirtualDevice> {
        self.devices.iter().filter(|d| d.class == class).collect()
    }

    pub fn enumerate_by_tier(&self, tier: ProxyTier) -> Vec<&VirtualDevice> {
        self.devices.iter().filter(|d| d.tier == tier).collect()
    }

    pub fn find_by_win32_path(&self, path: &str) -> Option<&VirtualDevice> {
        self.devices.iter().find(|d| d.win32_path == path)
    }

    pub fn find_by_linux_path(&self, path: &str) -> Option<&VirtualDevice> {
        self.devices.iter().find(|d| d.linux_path == path)
    }

    pub fn all_devices(&self) -> &[VirtualDevice] {
        &self.devices
    }

    pub fn simulate_hotplug(&mut self, event: HotplugEvent) -> Result<(), DeviceError> {
        match event.action {
            HotplugAction::Add => {
                if self.devices.iter().any(|d| d.win32_path == event.device_path) {
                    return Err(DeviceError::Duplicate(event.device_path));
                }
                self.devices.push(VirtualDevice {
                    class: event.class,
                    win32_path: event.device_path,
                    linux_path: format!(
                        "/dev/{}/hotplug{}",
                        event.class.linux_subsystem(),
                        self.devices.len()
                    ),
                    tier: ProxyTier::Tier3,
                    status: DeviceStatus::Partial,
                    notes: "hotplugged device".into(),
                });
                Ok(())
            }
            HotplugAction::Remove => {
                let before = self.devices.len();
                self.devices.retain(|d| d.win32_path != event.device_path);
                if self.devices.len() == before {
                    Err(DeviceError::NotFound(event.device_path))
                } else {
                    Ok(())
                }
            }
            HotplugAction::Change => {
                let dev = self
                    .devices
                    .iter_mut()
                    .find(|d| d.win32_path == event.device_path)
                    .ok_or_else(|| DeviceError::NotFound(event.device_path.clone()))?;
                dev.notes = format!("changed: {}", dev.notes);
                Ok(())
            }
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ComPortMapper {
    mappings: Vec<(String, String)>,
}

impl ComPortMapper {
    pub fn new() -> Self {
        Self { mappings: Vec::new() }
    }

    pub fn map_port(&mut self, win32_port: &str, linux_tty: &str) {
        if let Some(entry) = self.mappings.iter_mut().find(|(w, _)| w == win32_port) {
            entry.1 = linux_tty.to_string();
        } else {
            self.mappings.push((win32_port.to_string(), linux_tty.to_string()));
        }
    }

    pub fn get_linux_path(&self, win32_port: &str) -> Option<&str> {
        self.mappings
            .iter()
            .find(|(w, _)| w == win32_port)
            .map(|(_, l)| l.as_str())
    }

    pub fn list_mapped_ports(&self) -> Vec<(&str, &str)> {
        self.mappings
            .iter()
            .map(|(w, l)| (w.as_str(), l.as_str()))
            .collect()
    }
}

pub fn default_device_map() -> Vec<VirtualDevice> {
    vec![
        VirtualDevice {
            class: DeviceClass::Gpu,
            win32_path: r"\\.\DISPLAY1".into(),
            linux_path: "/dev/dri/card0".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "via graphics-stack".into(),
        },
        VirtualDevice {
            class: DeviceClass::Audio,
            win32_path: r"\\.\Audio0".into(),
            linux_path: "pipewire:default".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "via WASAPI bridge".into(),
        },
        VirtualDevice {
            class: DeviceClass::Keyboard,
            win32_path: r"\\.\Keyboard".into(),
            linux_path: "/dev/input/event*".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "evdev mapping".into(),
        },
        VirtualDevice {
            class: DeviceClass::Mouse,
            win32_path: r"\\.\Mouse".into(),
            linux_path: "/dev/input/event*".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "evdev mapping".into(),
        },
        VirtualDevice {
            class: DeviceClass::Gamepad,
            win32_path: r"\\.\XInput0".into(),
            linux_path: "/dev/input/js*".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "XInput stub".into(),
        },
        VirtualDevice {
            class: DeviceClass::SerialCom,
            win32_path: r"\\.\COM1".into(),
            linux_path: "/dev/ttyUSB0".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "COM port mapping".into(),
        },
        VirtualDevice {
            class: DeviceClass::Printer,
            win32_path: r"\\.\Printer0".into(),
            linux_path: "cups://default".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "Win32 spooler→CUPS; scan→SANE/IPP".into(),
        },
        VirtualDevice {
            class: DeviceClass::UsbHid,
            win32_path: r"\\.\HID0".into(),
            linux_path: "/dev/hidraw*".into(),
            tier: ProxyTier::Tier2,
            status: DeviceStatus::Partial,
            notes: "SetupAPI enum stub".into(),
        },
        VirtualDevice {
            class: DeviceClass::Network,
            win32_path: r"\\.\Npcap".into(),
            linux_path: "N/A".into(),
            tier: ProxyTier::Tier3,
            status: DeviceStatus::Fail,
            notes: "no .sys loaded; probe-only".into(),
        },
        VirtualDevice {
            class: DeviceClass::Storage,
            win32_path: r"\\.\PhysicalDrive0".into(),
            linux_path: "/dev/sda".into(),
            tier: ProxyTier::Tier1,
            status: DeviceStatus::Partial,
            notes: "block device mapping".into(),
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_map_populated() {
        let devices = default_device_map();
        assert!(!devices.is_empty());
        assert!(devices.len() >= 8);
    }

    #[test]
    fn device_classes_have_linux_subsystem() {
        let classes = [
            DeviceClass::Gpu, DeviceClass::Audio, DeviceClass::Keyboard,
            DeviceClass::Mouse, DeviceClass::Gamepad, DeviceClass::SerialCom,
            DeviceClass::Printer, DeviceClass::UsbHid,
        ];
        for class in classes {
            assert!(!class.linux_subsystem().is_empty());
            assert!(!class.as_str().is_empty());
        }
    }

    #[test]
    fn honest_status_no_fake_pass() {
        let devices = default_device_map();
        for dev in &devices {
            assert!(
                dev.status == DeviceStatus::Partial || dev.status == DeviceStatus::Fail,
                "v3.0 should not claim PASS for device: {}", dev.win32_path
            );
        }
    }

    #[test]
    fn enumerator_by_class() {
        let enumerator = DeviceEnumerator::new(default_device_map());
        let gpus = enumerator.enumerate_by_class(DeviceClass::Gpu);
        assert_eq!(gpus.len(), 1);
        assert_eq!(gpus[0].class, DeviceClass::Gpu);
    }

    #[test]
    fn enumerator_by_tier() {
        let enumerator = DeviceEnumerator::new(default_device_map());
        let tier1 = enumerator.enumerate_by_tier(ProxyTier::Tier1);
        assert!(tier1.len() >= 5);
        for dev in &tier1 {
            assert_eq!(dev.tier, ProxyTier::Tier1);
        }
    }

    #[test]
    fn enumerator_find_by_win32_path() {
        let enumerator = DeviceEnumerator::new(default_device_map());
        let dev = enumerator.find_by_win32_path(r"\\.\DISPLAY1");
        assert!(dev.is_some());
        assert_eq!(dev.unwrap().class, DeviceClass::Gpu);
        assert!(enumerator.find_by_win32_path(r"\\.\NoSuchDevice").is_none());
    }

    #[test]
    fn enumerator_find_by_linux_path() {
        let enumerator = DeviceEnumerator::new(default_device_map());
        let dev = enumerator.find_by_linux_path("/dev/dri/card0");
        assert!(dev.is_some());
        assert_eq!(dev.unwrap().class, DeviceClass::Gpu);
    }

    #[test]
    fn hotplug_add_and_remove() {
        let mut enumerator = DeviceEnumerator::new(default_device_map());
        let initial_count = enumerator.all_devices().len();

        let event = HotplugEvent {
            class: DeviceClass::UsbHid,
            action: HotplugAction::Add,
            device_path: r"\\.\HID_NEW".into(),
        };
        assert!(enumerator.simulate_hotplug(event).is_ok());
        assert_eq!(enumerator.all_devices().len(), initial_count + 1);
        assert!(enumerator.find_by_win32_path(r"\\.\HID_NEW").is_some());

        let remove = HotplugEvent {
            class: DeviceClass::UsbHid,
            action: HotplugAction::Remove,
            device_path: r"\\.\HID_NEW".into(),
        };
        assert!(enumerator.simulate_hotplug(remove).is_ok());
        assert_eq!(enumerator.all_devices().len(), initial_count);
    }

    #[test]
    fn hotplug_duplicate_rejected() {
        let mut enumerator = DeviceEnumerator::new(default_device_map());
        let event = HotplugEvent {
            class: DeviceClass::Gpu,
            action: HotplugAction::Add,
            device_path: r"\\.\DISPLAY1".into(),
        };
        assert!(enumerator.simulate_hotplug(event).is_err());
    }

    #[test]
    fn hotplug_change_updates_notes() {
        let mut enumerator = DeviceEnumerator::new(default_device_map());
        let event = HotplugEvent {
            class: DeviceClass::Gpu,
            action: HotplugAction::Change,
            device_path: r"\\.\DISPLAY1".into(),
        };
        assert!(enumerator.simulate_hotplug(event).is_ok());
        let dev = enumerator.find_by_win32_path(r"\\.\DISPLAY1").unwrap();
        assert!(dev.notes.starts_with("changed:"));
    }

    #[test]
    fn com_port_mapper() {
        let mut mapper = ComPortMapper::new();
        mapper.map_port("COM1", "/dev/ttyUSB0");
        mapper.map_port("COM3", "/dev/ttyS1");

        assert_eq!(mapper.get_linux_path("COM1"), Some("/dev/ttyUSB0"));
        assert_eq!(mapper.get_linux_path("COM3"), Some("/dev/ttyS1"));
        assert_eq!(mapper.get_linux_path("COM2"), None);

        let ports = mapper.list_mapped_ports();
        assert_eq!(ports.len(), 2);

        mapper.map_port("COM1", "/dev/ttyUSB1");
        assert_eq!(mapper.get_linux_path("COM1"), Some("/dev/ttyUSB1"));
        assert_eq!(mapper.list_mapped_ports().len(), 2);
    }

    #[test]
    fn hotplug_remove_nonexistent_fails() {
        let mut enumerator = DeviceEnumerator::new(Vec::new());
        let event = HotplugEvent {
            class: DeviceClass::Mouse,
            action: HotplugAction::Remove,
            device_path: r"\\.\Ghost".into(),
        };
        assert!(enumerator.simulate_hotplug(event).is_err());
    }
}
