use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxgiAdapter {
    pub description: String,
    pub vendor_id: u32,
    pub device_id: u32,
    pub dedicated_video_memory: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxgiTranslator {
    pub adapters: Vec<DxgiAdapter>,
    pub initialized: bool,
}

impl DxgiTranslator {
    pub fn new() -> Self {
        Self {
            adapters: Vec::new(),
            initialized: false,
        }
    }

    pub fn create_factory(&mut self) -> Result<(), DxgiError> {
        self.adapters.push(DxgiAdapter {
            description: "StrawWU DXGI→Vulkan Adapter".into(),
            vendor_id: 0x1337,
            device_id: 0x0001,
            dedicated_video_memory: 256 * 1024 * 1024,
        });
        self.initialized = true;
        Ok(())
    }

    pub fn enum_adapters(&self) -> Result<&[DxgiAdapter], DxgiError> {
        if !self.initialized {
            return Err(DxgiError::NotInitialized);
        }
        Ok(&self.adapters)
    }

    pub fn create_swap_chain(&self) -> Result<u64, DxgiError> {
        if !self.initialized {
            return Err(DxgiError::NotInitialized);
        }
        Ok(0x5743_0001) // swap chain handle stub
    }
}

impl Default for DxgiTranslator {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum DxgiError {
    #[error("DXGI factory not initialized")]
    NotInitialized,
    #[error("adapter not found")]
    AdapterNotFound,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dxgi_factory_init() {
        let mut dxgi = DxgiTranslator::new();
        assert!(!dxgi.initialized);
        dxgi.create_factory().unwrap();
        assert!(dxgi.initialized);
    }

    #[test]
    fn dxgi_enum_adapters() {
        let mut dxgi = DxgiTranslator::new();
        dxgi.create_factory().unwrap();
        let adapters = dxgi.enum_adapters().unwrap();
        assert!(!adapters.is_empty());
        assert!(adapters[0].description.contains("StrawWU"));
    }

    #[test]
    fn dxgi_swap_chain() {
        let mut dxgi = DxgiTranslator::new();
        dxgi.create_factory().unwrap();
        let handle = dxgi.create_swap_chain().unwrap();
        assert!(handle != 0);
    }

    #[test]
    fn dxgi_uninit_fails() {
        let dxgi = DxgiTranslator::new();
        assert!(dxgi.enum_adapters().is_err());
        assert!(dxgi.create_swap_chain().is_err());
    }
}
