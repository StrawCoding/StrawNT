use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VkResult {
    Success,
    NotReady,
    ErrorOutOfHostMemory,
    ErrorInitializationFailed,
    ErrorDeviceLost,
    ErrorLayerNotPresent,
    ErrorExtensionNotPresent,
    ErrorFeatureNotPresent,
}

impl VkResult {
    pub fn is_success(&self) -> bool {
        matches!(self, Self::Success | Self::NotReady)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VulkanPhysicalDevice {
    pub name: String,
    pub api_version: String,
    pub driver_version: String,
    pub vendor_id: u32,
    pub device_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VulkanIcd {
    pub icd_name: String,
    pub api_version: String,
    pub instance_extensions: Vec<String>,
    pub physical_devices: Vec<VulkanPhysicalDevice>,
    pub initialized: bool,
}

impl VulkanIcd {
    pub fn new() -> Self {
        Self {
            icd_name: "strawwu-vk-icd".to_string(),
            api_version: "1.3.0".to_string(),
            instance_extensions: vec![
                "VK_KHR_surface".into(),
                "VK_KHR_wayland_surface".into(),
                "VK_KHR_xcb_surface".into(),
            ],
            physical_devices: Vec::new(),
            initialized: false,
        }
    }

    pub fn initialize(&mut self) -> VkResult {
        self.physical_devices.push(VulkanPhysicalDevice {
            name: "StrawWU Vulkan Passthrough".into(),
            api_version: "1.3.0".into(),
            driver_version: "0.3.0".into(),
            vendor_id: 0x1337,
            device_type: "integrated_gpu".into(),
        });
        self.initialized = true;
        VkResult::Success
    }

    pub fn enumerate_physical_devices(&self) -> Result<&[VulkanPhysicalDevice], VkResult> {
        if !self.initialized {
            return Err(VkResult::ErrorInitializationFailed);
        }
        Ok(&self.physical_devices)
    }

    pub fn supports_extension(&self, name: &str) -> bool {
        self.instance_extensions.iter().any(|e| e == name)
    }
}

impl Default for VulkanIcd {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vulkan_icd_init() {
        let mut icd = VulkanIcd::new();
        assert!(!icd.initialized);

        let result = icd.initialize();
        assert_eq!(result, VkResult::Success);
        assert!(icd.initialized);
    }

    #[test]
    fn vulkan_enumerate_devices() {
        let mut icd = VulkanIcd::new();
        icd.initialize();

        let devices = icd.enumerate_physical_devices().unwrap();
        assert!(!devices.is_empty());
        assert!(devices[0].name.contains("StrawWU"));
    }

    #[test]
    fn vulkan_not_initialized_fails() {
        let icd = VulkanIcd::new();
        assert!(icd.enumerate_physical_devices().is_err());
    }

    #[test]
    fn vulkan_extensions() {
        let icd = VulkanIcd::new();
        assert!(icd.supports_extension("VK_KHR_surface"));
        assert!(!icd.supports_extension("VK_EXT_nonexistent"));
    }
}
