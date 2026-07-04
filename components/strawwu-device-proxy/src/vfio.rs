use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VfioDeviceType {
    Gpu,
    UsbController,
    NvmeSsd,
    NetworkAdapter,
}

impl VfioDeviceType {
    pub fn pci_class_code(&self) -> u32 {
        match self {
            Self::Gpu => 0x0300,
            Self::UsbController => 0x0C03,
            Self::NvmeSsd => 0x0108,
            Self::NetworkAdapter => 0x0200,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Gpu => "VGA compatible controller",
            Self::UsbController => "USB controller",
            Self::NvmeSsd => "NVMe storage controller",
            Self::NetworkAdapter => "Ethernet controller",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum BindState {
    HostDriver(String),
    VfioPci,
    Unbound,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PciAddress {
    pub domain: u16,
    pub bus: u8,
    pub device: u8,
    pub function: u8,
}

impl PciAddress {
    pub fn new(domain: u16, bus: u8, device: u8, function: u8) -> Self {
        Self { domain, bus, device, function }
    }

    pub fn bdf_string(&self) -> String {
        format!("{:04x}:{:02x}:{:02x}.{}", self.domain, self.bus, self.device, self.function)
    }
}

impl std::fmt::Display for PciAddress {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.bdf_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PciConfigSpace {
    pub vendor_id: u16,
    pub device_id: u16,
    pub class_code: u32,
    pub subsystem_vendor_id: u16,
    pub subsystem_device_id: u16,
    pub revision_id: u8,
    pub bar: [u64; 6],
    pub interrupt_pin: u8,
    pub interrupt_line: u8,
}

impl PciConfigSpace {
    pub fn read_u32(&self, offset: u32) -> u32 {
        match offset {
            0x00 => (self.device_id as u32) << 16 | self.vendor_id as u32,
            0x08 => (self.class_code << 8) | self.revision_id as u32,
            0x2C => (self.subsystem_device_id as u32) << 16 | self.subsystem_vendor_id as u32,
            0x10..=0x24 => {
                let bar_idx = ((offset - 0x10) / 4) as usize;
                if bar_idx < 6 { self.bar[bar_idx] as u32 } else { 0 }
            }
            0x3C => (self.interrupt_pin as u32) << 8 | self.interrupt_line as u32,
            _ => 0xFFFF_FFFF,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VfioDevice {
    pub address: PciAddress,
    pub device_type: VfioDeviceType,
    pub iommu_group: u32,
    pub bind_state: BindState,
    pub config: PciConfigSpace,
    pub numa_node: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IommuGroup {
    pub id: u32,
    pub devices: Vec<PciAddress>,
    pub viable: bool,
}

impl IommuGroup {
    pub fn is_isolated(&self) -> bool {
        self.devices.len() == 1
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InterruptMode {
    Legacy,
    Msi,
    MsiX,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InterruptRouting {
    pub device: PciAddress,
    pub mode: InterruptMode,
    pub vector_count: u32,
    pub enabled: bool,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum VfioError {
    #[error("IOMMU not available")]
    IommuNotAvailable,
    #[error("device {0} not found")]
    DeviceNotFound(String),
    #[error("device {0} already bound to vfio-pci")]
    AlreadyBound(String),
    #[error("device {0} not bound to vfio-pci")]
    NotBound(String),
    #[error("IOMMU group {0} not viable for passthrough")]
    GroupNotViable(u32),
    #[error("container not open")]
    ContainerNotOpen,
    #[error("device {0} is in a shared IOMMU group — all devices must be unbound")]
    SharedGroup(String),
    #[error("PCI config read out of bounds: offset {0}")]
    ConfigReadOob(u32),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContainerState {
    Closed,
    Open,
    GroupAttached,
    IommuSet,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VfioContainer {
    pub state: ContainerState,
    pub attached_groups: Vec<u32>,
}

impl VfioContainer {
    pub fn new() -> Self {
        Self {
            state: ContainerState::Closed,
            attached_groups: Vec::new(),
        }
    }

    pub fn open(&mut self) {
        self.state = ContainerState::Open;
    }

    pub fn attach_group(&mut self, group_id: u32) -> Result<(), VfioError> {
        if self.state == ContainerState::Closed {
            return Err(VfioError::ContainerNotOpen);
        }
        if !self.attached_groups.contains(&group_id) {
            self.attached_groups.push(group_id);
        }
        self.state = ContainerState::GroupAttached;
        Ok(())
    }

    pub fn set_iommu_type1(&mut self) -> Result<(), VfioError> {
        if self.state == ContainerState::Closed {
            return Err(VfioError::ContainerNotOpen);
        }
        self.state = ContainerState::IommuSet;
        Ok(())
    }

    pub fn is_ready(&self) -> bool {
        self.state == ContainerState::IommuSet
    }
}

impl Default for VfioContainer {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Default)]
pub struct VfioManager {
    pub iommu_available: bool,
    devices: Vec<VfioDevice>,
    groups: Vec<IommuGroup>,
    interrupts: Vec<InterruptRouting>,
    container: VfioContainer,
    dma_mappings: HashMap<u64, u64>,
}

impl VfioManager {
    pub fn new(iommu_available: bool) -> Self {
        Self {
            iommu_available,
            container: VfioContainer::new(),
            ..Default::default()
        }
    }

    pub fn scan_iommu_groups(&mut self) -> Result<&[IommuGroup], VfioError> {
        if !self.iommu_available {
            return Err(VfioError::IommuNotAvailable);
        }
        self.groups.clear();
        for dev in &self.devices {
            if let Some(group) = self.groups.iter_mut().find(|g| g.id == dev.iommu_group) {
                group.devices.push(dev.address.clone());
            } else {
                self.groups.push(IommuGroup {
                    id: dev.iommu_group,
                    devices: vec![dev.address.clone()],
                    viable: true,
                });
            }
        }
        for group in &mut self.groups {
            group.viable = group.devices.iter().all(|addr| {
                self.devices
                    .iter()
                    .find(|d| d.address.bdf_string() == addr.bdf_string())
                    .map(|d| d.bind_state != BindState::HostDriver("bridge".into()))
                    .unwrap_or(false)
            });
        }
        Ok(&self.groups)
    }

    pub fn add_device(&mut self, device: VfioDevice) {
        self.devices.push(device);
    }

    pub fn get_device(&self, bdf: &str) -> Option<&VfioDevice> {
        self.devices.iter().find(|d| d.address.bdf_string() == bdf)
    }

    pub fn bind_to_vfio(&mut self, bdf: &str) -> Result<(), VfioError> {
        if !self.iommu_available {
            return Err(VfioError::IommuNotAvailable);
        }

        let dev = self.devices.iter_mut()
            .find(|d| d.address.bdf_string() == bdf)
            .ok_or_else(|| VfioError::DeviceNotFound(bdf.to_string()))?;

        if dev.bind_state == BindState::VfioPci {
            return Err(VfioError::AlreadyBound(bdf.to_string()));
        }

        let group_id = dev.iommu_group;
        let group_devices: Vec<String> = self.devices.iter()
            .filter(|d| d.iommu_group == group_id && d.address.bdf_string() != bdf)
            .map(|d| d.address.bdf_string())
            .collect();

        let has_shared_host_bound = self.devices.iter()
            .any(|d| d.iommu_group == group_id
                && d.address.bdf_string() != bdf
                && matches!(d.bind_state, BindState::HostDriver(_)));

        if has_shared_host_bound && !group_devices.is_empty() {
            return Err(VfioError::SharedGroup(bdf.to_string()));
        }

        let dev = self.devices.iter_mut()
            .find(|d| d.address.bdf_string() == bdf)
            .unwrap();
        dev.bind_state = BindState::VfioPci;
        Ok(())
    }

    pub fn unbind_from_vfio(&mut self, bdf: &str) -> Result<(), VfioError> {
        let dev = self.devices.iter_mut()
            .find(|d| d.address.bdf_string() == bdf)
            .ok_or_else(|| VfioError::DeviceNotFound(bdf.to_string()))?;

        if dev.bind_state != BindState::VfioPci {
            return Err(VfioError::NotBound(bdf.to_string()));
        }

        dev.bind_state = BindState::Unbound;
        Ok(())
    }

    pub fn read_pci_config(&self, bdf: &str, offset: u32) -> Result<u32, VfioError> {
        let dev = self.devices.iter()
            .find(|d| d.address.bdf_string() == bdf)
            .ok_or_else(|| VfioError::DeviceNotFound(bdf.to_string()))?;

        if offset > 0x100 {
            return Err(VfioError::ConfigReadOob(offset));
        }

        Ok(dev.config.read_u32(offset))
    }

    pub fn setup_interrupts(&mut self, bdf: &str, mode: InterruptMode, vectors: u32) -> Result<(), VfioError> {
        let dev = self.devices.iter()
            .find(|d| d.address.bdf_string() == bdf)
            .ok_or_else(|| VfioError::DeviceNotFound(bdf.to_string()))?;

        if dev.bind_state != BindState::VfioPci {
            return Err(VfioError::NotBound(bdf.to_string()));
        }

        self.interrupts.retain(|i| i.device.bdf_string() != bdf);
        self.interrupts.push(InterruptRouting {
            device: dev.address.clone(),
            mode,
            vector_count: vectors,
            enabled: true,
        });
        Ok(())
    }

    pub fn get_interrupt_routing(&self, bdf: &str) -> Option<&InterruptRouting> {
        self.interrupts.iter().find(|i| i.device.bdf_string() == bdf)
    }

    pub fn open_container(&mut self) -> Result<(), VfioError> {
        if !self.iommu_available {
            return Err(VfioError::IommuNotAvailable);
        }
        self.container.open();
        Ok(())
    }

    pub fn attach_group_to_container(&mut self, group_id: u32) -> Result<(), VfioError> {
        let group = self.groups.iter()
            .find(|g| g.id == group_id)
            .ok_or(VfioError::GroupNotViable(group_id))?;

        if !group.viable {
            return Err(VfioError::GroupNotViable(group_id));
        }

        self.container.attach_group(group_id)
    }

    pub fn set_iommu(&mut self) -> Result<(), VfioError> {
        self.container.set_iommu_type1()
    }

    pub fn map_dma(&mut self, iova: u64, size: u64) -> Result<(), VfioError> {
        if !self.container.is_ready() {
            return Err(VfioError::ContainerNotOpen);
        }
        self.dma_mappings.insert(iova, size);
        Ok(())
    }

    pub fn unmap_dma(&mut self, iova: u64) -> Result<(), VfioError> {
        if !self.container.is_ready() {
            return Err(VfioError::ContainerNotOpen);
        }
        self.dma_mappings.remove(&iova);
        Ok(())
    }

    pub fn dma_mapping_count(&self) -> usize {
        self.dma_mappings.len()
    }

    pub fn container_state(&self) -> ContainerState {
        self.container.state
    }

    pub fn all_devices(&self) -> &[VfioDevice] {
        &self.devices
    }

    pub fn all_groups(&self) -> &[IommuGroup] {
        &self.groups
    }

    pub fn passthrough_capable_devices(&self) -> Vec<&VfioDevice> {
        self.devices.iter()
            .filter(|d| d.bind_state == BindState::VfioPci)
            .collect()
    }

    pub fn status_summary(&self) -> VfioStatusSummary {
        VfioStatusSummary {
            iommu_available: self.iommu_available,
            total_devices: self.devices.len(),
            vfio_bound: self.devices.iter().filter(|d| d.bind_state == BindState::VfioPci).count(),
            groups_scanned: self.groups.len(),
            viable_groups: self.groups.iter().filter(|g| g.viable).count(),
            container_state: self.container.state,
            dma_mappings: self.dma_mappings.len(),
            interrupt_routes: self.interrupts.len(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VfioStatusSummary {
    pub iommu_available: bool,
    pub total_devices: usize,
    pub vfio_bound: usize,
    pub groups_scanned: usize,
    pub viable_groups: usize,
    pub container_state: ContainerState,
    pub dma_mappings: usize,
    pub interrupt_routes: usize,
}

pub fn create_test_gpu() -> VfioDevice {
    VfioDevice {
        address: PciAddress::new(0, 1, 0, 0),
        device_type: VfioDeviceType::Gpu,
        iommu_group: 1,
        bind_state: BindState::HostDriver("nvidia".into()),
        config: PciConfigSpace {
            vendor_id: 0x10DE,
            device_id: 0x2684,
            class_code: 0x0300,
            subsystem_vendor_id: 0x10DE,
            subsystem_device_id: 0x16A1,
            revision_id: 0xA1,
            bar: [0xFB00_0000, 0xD000_0000, 0xDC00_0000, 0, 0, 0],
            interrupt_pin: 1,
            interrupt_line: 11,
        },
        numa_node: 0,
    }
}

pub fn create_test_usb_controller() -> VfioDevice {
    VfioDevice {
        address: PciAddress::new(0, 0, 0x14, 0),
        device_type: VfioDeviceType::UsbController,
        iommu_group: 2,
        bind_state: BindState::HostDriver("xhci_hcd".into()),
        config: PciConfigSpace {
            vendor_id: 0x8086,
            device_id: 0xA36D,
            class_code: 0x0C03,
            subsystem_vendor_id: 0x8086,
            subsystem_device_id: 0x7270,
            revision_id: 0x10,
            bar: [0xED31_0000, 0, 0, 0, 0, 0],
            interrupt_pin: 1,
            interrupt_line: 16,
        },
        numa_node: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_manager() -> VfioManager {
        let mut mgr = VfioManager::new(true);
        mgr.add_device(create_test_gpu());
        mgr.add_device(create_test_usb_controller());
        mgr
    }

    #[test]
    fn pci_address_bdf_format() {
        let addr = PciAddress::new(0, 1, 0, 0);
        assert_eq!(addr.bdf_string(), "0000:01:00.0");
        assert_eq!(format!("{}", addr), "0000:01:00.0");
    }

    #[test]
    fn pci_config_read_vendor_device() {
        let gpu = create_test_gpu();
        let val = gpu.config.read_u32(0x00);
        assert_eq!(val & 0xFFFF, 0x10DE);
        assert_eq!(val >> 16, 0x2684);
    }

    #[test]
    fn pci_config_read_class() {
        let gpu = create_test_gpu();
        let val = gpu.config.read_u32(0x08);
        assert_eq!(val >> 8, 0x0300);
    }

    #[test]
    fn pci_config_read_bars() {
        let gpu = create_test_gpu();
        assert_eq!(gpu.config.read_u32(0x10), 0xFB00_0000);
        assert_eq!(gpu.config.read_u32(0x14), 0xD000_0000);
    }

    #[test]
    fn pci_config_read_interrupt() {
        let gpu = create_test_gpu();
        let val = gpu.config.read_u32(0x3C);
        assert_eq!(val & 0xFF, 11);
        assert_eq!((val >> 8) & 0xFF, 1);
    }

    #[test]
    fn pci_config_read_unknown_returns_ff() {
        let gpu = create_test_gpu();
        assert_eq!(gpu.config.read_u32(0x50), 0xFFFF_FFFF);
    }

    #[test]
    fn scan_iommu_groups() {
        let mut mgr = setup_manager();
        let groups = mgr.scan_iommu_groups().unwrap();
        assert_eq!(groups.len(), 2);
        assert!(groups.iter().any(|g| g.id == 1));
        assert!(groups.iter().any(|g| g.id == 2));
    }

    #[test]
    fn iommu_group_isolated() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        for group in mgr.all_groups() {
            assert!(group.is_isolated());
        }
    }

    #[test]
    fn scan_iommu_fails_without_iommu() {
        let mut mgr = VfioManager::new(false);
        mgr.add_device(create_test_gpu());
        assert!(mgr.scan_iommu_groups().is_err());
    }

    #[test]
    fn bind_unbind_vfio() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        let bdf = "0000:01:00.0";

        assert!(mgr.bind_to_vfio(bdf).is_ok());
        assert_eq!(mgr.get_device(bdf).unwrap().bind_state, BindState::VfioPci);

        assert!(mgr.unbind_from_vfio(bdf).is_ok());
        assert_eq!(mgr.get_device(bdf).unwrap().bind_state, BindState::Unbound);
    }

    #[test]
    fn double_bind_rejected() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        let bdf = "0000:01:00.0";
        mgr.bind_to_vfio(bdf).unwrap();
        assert!(mgr.bind_to_vfio(bdf).is_err());
    }

    #[test]
    fn unbind_not_bound_rejected() {
        let mut mgr = setup_manager();
        let bdf = "0000:01:00.0";
        assert!(mgr.unbind_from_vfio(bdf).is_err());
    }

    #[test]
    fn bind_nonexistent_device() {
        let mut mgr = setup_manager();
        assert!(mgr.bind_to_vfio("0000:FF:FF.0").is_err());
    }

    #[test]
    fn read_pci_config_via_manager() {
        let mgr = setup_manager();
        let val = mgr.read_pci_config("0000:01:00.0", 0x00).unwrap();
        assert_eq!(val & 0xFFFF, 0x10DE);
    }

    #[test]
    fn read_pci_config_oob() {
        let mgr = setup_manager();
        assert!(mgr.read_pci_config("0000:01:00.0", 0x200).is_err());
    }

    #[test]
    fn interrupt_setup_requires_vfio_bind() {
        let mut mgr = setup_manager();
        let bdf = "0000:01:00.0";
        assert!(mgr.setup_interrupts(bdf, InterruptMode::MsiX, 32).is_err());

        mgr.scan_iommu_groups().unwrap();
        mgr.bind_to_vfio(bdf).unwrap();
        assert!(mgr.setup_interrupts(bdf, InterruptMode::MsiX, 32).is_ok());

        let routing = mgr.get_interrupt_routing(bdf).unwrap();
        assert_eq!(routing.mode, InterruptMode::MsiX);
        assert_eq!(routing.vector_count, 32);
        assert!(routing.enabled);
    }

    #[test]
    fn container_lifecycle() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        mgr.bind_to_vfio("0000:01:00.0").unwrap();

        assert_eq!(mgr.container_state(), ContainerState::Closed);

        mgr.open_container().unwrap();
        assert_eq!(mgr.container_state(), ContainerState::Open);

        mgr.attach_group_to_container(1).unwrap();
        assert_eq!(mgr.container_state(), ContainerState::GroupAttached);

        mgr.set_iommu().unwrap();
        assert_eq!(mgr.container_state(), ContainerState::IommuSet);
    }

    #[test]
    fn container_open_fails_without_iommu() {
        let mut mgr = VfioManager::new(false);
        assert!(mgr.open_container().is_err());
    }

    #[test]
    fn dma_mapping() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        mgr.bind_to_vfio("0000:01:00.0").unwrap();
        mgr.open_container().unwrap();
        mgr.attach_group_to_container(1).unwrap();
        mgr.set_iommu().unwrap();

        assert_eq!(mgr.dma_mapping_count(), 0);
        mgr.map_dma(0x1000_0000, 0x0100_0000).unwrap();
        mgr.map_dma(0x2000_0000, 0x0200_0000).unwrap();
        assert_eq!(mgr.dma_mapping_count(), 2);

        mgr.unmap_dma(0x1000_0000).unwrap();
        assert_eq!(mgr.dma_mapping_count(), 1);
    }

    #[test]
    fn dma_requires_ready_container() {
        let mut mgr = setup_manager();
        assert!(mgr.map_dma(0x1000, 0x100).is_err());
    }

    #[test]
    fn passthrough_capable_filter() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        assert_eq!(mgr.passthrough_capable_devices().len(), 0);

        mgr.bind_to_vfio("0000:01:00.0").unwrap();
        assert_eq!(mgr.passthrough_capable_devices().len(), 1);
        assert_eq!(mgr.passthrough_capable_devices()[0].device_type, VfioDeviceType::Gpu);
    }

    #[test]
    fn status_summary() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        mgr.bind_to_vfio("0000:01:00.0").unwrap();

        let summary = mgr.status_summary();
        assert!(summary.iommu_available);
        assert_eq!(summary.total_devices, 2);
        assert_eq!(summary.vfio_bound, 1);
        assert_eq!(summary.groups_scanned, 2);
        assert!(summary.viable_groups >= 1);
    }

    #[test]
    fn device_type_pci_class() {
        assert_eq!(VfioDeviceType::Gpu.pci_class_code(), 0x0300);
        assert_eq!(VfioDeviceType::UsbController.pci_class_code(), 0x0C03);
        assert_eq!(VfioDeviceType::NvmeSsd.pci_class_code(), 0x0108);
        assert_eq!(VfioDeviceType::NetworkAdapter.pci_class_code(), 0x0200);
    }

    #[test]
    fn device_type_names() {
        assert!(!VfioDeviceType::Gpu.as_str().is_empty());
        assert!(!VfioDeviceType::UsbController.as_str().is_empty());
    }

    #[test]
    fn shared_iommu_group_blocks_partial_bind() {
        let mut mgr = VfioManager::new(true);
        let mut gpu = create_test_gpu();
        gpu.iommu_group = 5;
        let gpu2 = VfioDevice {
            address: PciAddress::new(0, 1, 0, 1),
            device_type: VfioDeviceType::Gpu,
            iommu_group: 5,
            bind_state: BindState::HostDriver("nvidia".into()),
            config: gpu.config.clone(),
            numa_node: 0,
        };
        mgr.add_device(gpu);
        mgr.add_device(gpu2);
        mgr.scan_iommu_groups().unwrap();

        let result = mgr.bind_to_vfio("0000:01:00.0");
        assert!(result.is_err());
    }

    #[test]
    fn full_passthrough_flow() {
        let mut mgr = setup_manager();

        mgr.scan_iommu_groups().unwrap();
        assert_eq!(mgr.all_groups().len(), 2);

        let bdf = "0000:01:00.0";
        mgr.bind_to_vfio(bdf).unwrap();

        let vendor = mgr.read_pci_config(bdf, 0x00).unwrap();
        assert_eq!(vendor & 0xFFFF, 0x10DE);

        mgr.setup_interrupts(bdf, InterruptMode::MsiX, 16).unwrap();

        mgr.open_container().unwrap();
        mgr.attach_group_to_container(1).unwrap();
        mgr.set_iommu().unwrap();

        mgr.map_dma(0x8000_0000, 0x1000_0000).unwrap();

        let summary = mgr.status_summary();
        assert_eq!(summary.vfio_bound, 1);
        assert_eq!(summary.dma_mappings, 1);
        assert_eq!(summary.interrupt_routes, 1);
        assert_eq!(summary.container_state, ContainerState::IommuSet);
    }

    #[test]
    fn container_attach_nonviable_group_fails() {
        let mut mgr = setup_manager();
        mgr.scan_iommu_groups().unwrap();
        mgr.open_container().unwrap();
        assert!(mgr.attach_group_to_container(999).is_err());
    }
}
