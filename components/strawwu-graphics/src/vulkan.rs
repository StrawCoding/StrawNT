use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VkResult {
    Success,
    NotReady,
    Timeout,
    Suboptimal,
    ErrorOutOfHostMemory,
    ErrorInitializationFailed,
    ErrorDeviceLost,
    ErrorSurfaceLost,
    ErrorLayerNotPresent,
    ErrorExtensionNotPresent,
    ErrorFeatureNotPresent,
    ErrorOutOfDateKhr,
}

impl VkResult {
    pub fn is_success(&self) -> bool {
        matches!(self, Self::Success | Self::NotReady | Self::Suboptimal)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VulkanPhysicalDevice {
    pub name: String,
    pub api_version: String,
    pub driver_version: String,
    pub vendor_id: u32,
    pub device_type: String,
    pub queue_family_count: u32,
    pub max_image_dimension_2d: u32,
    pub max_memory_allocation_count: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkInstance(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkDevice(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkSurface(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkSwapchain(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkQueue(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct VkCommandPool(pub u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VkPresentMode {
    Immediate,
    Mailbox,
    Fifo,
    FifoRelaxed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapchainConfig {
    pub width: u32,
    pub height: u32,
    pub image_count: u32,
    pub present_mode: VkPresentMode,
    pub format: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VulkanIcd {
    pub icd_name: String,
    pub api_version: String,
    pub instance_extensions: Vec<String>,
    pub device_extensions: Vec<String>,
    pub physical_devices: Vec<VulkanPhysicalDevice>,
    pub initialized: bool,
    instance: Option<VkInstance>,
    device: Option<VkDevice>,
    surface: Option<VkSurface>,
    swapchain: Option<VkSwapchain>,
    graphics_queue: Option<VkQueue>,
    present_queue: Option<VkQueue>,
    command_pool: Option<VkCommandPool>,
    next_handle: u64,
    frame_index: u64,
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
                "VK_EXT_debug_utils".into(),
            ],
            device_extensions: vec![
                "VK_KHR_swapchain".into(),
                "VK_KHR_maintenance1".into(),
                "VK_KHR_dynamic_rendering".into(),
            ],
            physical_devices: Vec::new(),
            initialized: false,
            instance: None,
            device: None,
            surface: None,
            swapchain: None,
            graphics_queue: None,
            present_queue: None,
            command_pool: None,
            next_handle: 0xAC00_0001,
            frame_index: 0,
        }
    }

    fn alloc_handle(&mut self) -> u64 {
        let h = self.next_handle;
        self.next_handle += 1;
        h
    }

    pub fn create_instance(&mut self, app_name: &str, api_version: &str) -> Result<VkInstance, VkResult> {
        let _ = (app_name, api_version);
        self.physical_devices.push(VulkanPhysicalDevice {
            name: "StrawWU Vulkan Passthrough".into(),
            api_version: "1.3.0".into(),
            driver_version: "0.3.0".into(),
            vendor_id: 0x1337,
            device_type: "integrated_gpu".into(),
            queue_family_count: 3,
            max_image_dimension_2d: 16384,
            max_memory_allocation_count: 4096,
        });
        self.initialized = true;
        let inst = VkInstance(self.alloc_handle());
        self.instance = Some(inst);
        Ok(inst)
    }

    pub fn initialize(&mut self) -> VkResult {
        if self.instance.is_none() {
            let _ = self.create_instance("legacy", "1.3.0");
        }
        VkResult::Success
    }

    pub fn create_surface(&mut self, display_handle: u64) -> Result<VkSurface, VkResult> {
        if self.instance.is_none() {
            return Err(VkResult::ErrorInitializationFailed);
        }
        let _ = display_handle;
        let surface = VkSurface(self.alloc_handle());
        self.surface = Some(surface);
        Ok(surface)
    }

    pub fn create_device(&mut self, physical_device_index: usize) -> Result<VkDevice, VkResult> {
        if !self.initialized || physical_device_index >= self.physical_devices.len() {
            return Err(VkResult::ErrorInitializationFailed);
        }
        let dev = VkDevice(self.alloc_handle());
        self.device = Some(dev);

        self.graphics_queue = Some(VkQueue(self.alloc_handle()));
        self.present_queue = Some(VkQueue(self.alloc_handle()));

        Ok(dev)
    }

    pub fn create_swapchain(&mut self, config: &SwapchainConfig) -> Result<VkSwapchain, VkResult> {
        if self.device.is_none() || self.surface.is_none() {
            return Err(VkResult::ErrorInitializationFailed);
        }
        if config.width == 0 || config.height == 0 {
            return Err(VkResult::ErrorInitializationFailed);
        }
        let sc = VkSwapchain(self.alloc_handle());
        self.swapchain = Some(sc);
        Ok(sc)
    }

    pub fn create_command_pool(&mut self) -> Result<VkCommandPool, VkResult> {
        if self.device.is_none() {
            return Err(VkResult::ErrorInitializationFailed);
        }
        let pool = VkCommandPool(self.alloc_handle());
        self.command_pool = Some(pool);
        Ok(pool)
    }

    pub fn acquire_next_image(&mut self) -> Result<u32, VkResult> {
        if self.swapchain.is_none() {
            return Err(VkResult::ErrorOutOfDateKhr);
        }
        let idx = (self.frame_index % 3) as u32;
        Ok(idx)
    }

    pub fn queue_present(&mut self, _image_index: u32) -> Result<(), VkResult> {
        if self.swapchain.is_none() {
            return Err(VkResult::ErrorOutOfDateKhr);
        }
        self.frame_index += 1;
        Ok(())
    }

    pub fn enumerate_physical_devices(&self) -> Result<&[VulkanPhysicalDevice], VkResult> {
        if !self.initialized {
            return Err(VkResult::ErrorInitializationFailed);
        }
        Ok(&self.physical_devices)
    }

    pub fn supports_extension(&self, name: &str) -> bool {
        self.instance_extensions.iter().any(|e| e == name)
            || self.device_extensions.iter().any(|e| e == name)
    }

    pub fn get_graphics_queue(&self) -> Option<VkQueue> {
        self.graphics_queue
    }

    pub fn get_present_queue(&self) -> Option<VkQueue> {
        self.present_queue
    }

    pub fn frame_count(&self) -> u64 {
        self.frame_index
    }

    pub fn destroy(&mut self) {
        self.swapchain = None;
        self.command_pool = None;
        self.surface = None;
        self.device = None;
        self.graphics_queue = None;
        self.present_queue = None;
        self.instance = None;
        self.initialized = false;
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
    fn vulkan_full_pipeline() {
        let mut icd = VulkanIcd::new();

        // Create instance
        let inst = icd.create_instance("TestApp", "1.3.0").unwrap();
        assert!(inst.0 > 0);
        assert!(icd.initialized);

        // Enumerate physical devices
        let devices = icd.enumerate_physical_devices().unwrap();
        assert!(!devices.is_empty());
        assert!(devices[0].name.contains("StrawWU"));
        assert_eq!(devices[0].queue_family_count, 3);

        // Create surface
        let surface = icd.create_surface(0xABCD_0001).unwrap();
        assert!(surface.0 > 0);

        // Create device
        let dev = icd.create_device(0).unwrap();
        assert!(dev.0 > 0);
        assert!(icd.get_graphics_queue().is_some());
        assert!(icd.get_present_queue().is_some());

        // Create swapchain
        let sc = icd.create_swapchain(&SwapchainConfig {
            width: 1920,
            height: 1080,
            image_count: 3,
            present_mode: VkPresentMode::Fifo,
            format: 44, // VK_FORMAT_B8G8R8A8_UNORM
        }).unwrap();
        assert!(sc.0 > 0);

        // Create command pool
        let pool = icd.create_command_pool().unwrap();
        assert!(pool.0 > 0);

        // Render loop
        for _ in 0..5 {
            let img_idx = icd.acquire_next_image().unwrap();
            assert!(img_idx < 3);
            icd.queue_present(img_idx).unwrap();
        }
        assert_eq!(icd.frame_count(), 5);

        // Cleanup
        icd.destroy();
        assert!(!icd.initialized);
    }

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
        assert!(icd.supports_extension("VK_KHR_swapchain"));
        assert!(!icd.supports_extension("VK_EXT_nonexistent"));
    }

    #[test]
    fn vulkan_no_device_swapchain_fails() {
        let mut icd = VulkanIcd::new();
        icd.create_instance("App", "1.3.0").unwrap();
        assert!(icd.create_swapchain(&SwapchainConfig {
            width: 800,
            height: 600,
            image_count: 2,
            present_mode: VkPresentMode::Immediate,
            format: 44,
        }).is_err());
    }

    #[test]
    fn vulkan_present_without_swapchain_fails() {
        let mut icd = VulkanIcd::new();
        assert!(icd.acquire_next_image().is_err());
        assert!(icd.queue_present(0).is_err());
    }

    #[test]
    fn vulkan_create_surface_needs_instance() {
        let mut icd = VulkanIcd::new();
        assert!(icd.create_surface(0).is_err());
    }

    #[test]
    fn vulkan_present_modes() {
        let mut icd = VulkanIcd::new();
        icd.create_instance("App", "1.3.0").unwrap();
        icd.create_surface(1).unwrap();
        icd.create_device(0).unwrap();

        for mode in [VkPresentMode::Immediate, VkPresentMode::Mailbox, VkPresentMode::Fifo, VkPresentMode::FifoRelaxed] {
            let sc = icd.create_swapchain(&SwapchainConfig {
                width: 640,
                height: 480,
                image_count: 2,
                present_mode: mode,
                format: 44,
            });
            assert!(sc.is_ok());
        }
    }
}
