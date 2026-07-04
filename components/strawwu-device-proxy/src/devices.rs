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
            notes: "Win32 spooler→CUPS".into(),
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
}
