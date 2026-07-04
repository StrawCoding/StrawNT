use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxgiAdapter {
    pub description: String,
    pub vendor_id: u32,
    pub device_id: u32,
    pub dedicated_video_memory: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxgiOutput {
    pub name: String,
    pub width: u32,
    pub height: u32,
    pub refresh_rate_numerator: u32,
    pub refresh_rate_denominator: u32,
    pub attached_to_adapter: usize,
}

impl DxgiOutput {
    pub fn refresh_rate_hz(&self) -> f64 {
        if self.refresh_rate_denominator == 0 {
            return 0.0;
        }
        self.refresh_rate_numerator as f64 / self.refresh_rate_denominator as f64
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxgiTranslator {
    pub adapters: Vec<DxgiAdapter>,
    pub outputs: Vec<DxgiOutput>,
    pub initialized: bool,
    pub frame_count: u64,
}

impl DxgiTranslator {
    pub fn new() -> Self {
        Self {
            adapters: Vec::new(),
            outputs: Vec::new(),
            initialized: false,
            frame_count: 0,
        }
    }

    pub fn create_factory(&mut self) -> Result<(), DxgiError> {
        self.adapters.push(DxgiAdapter {
            description: "StrawWU DXGI→Vulkan Adapter".into(),
            vendor_id: 0x1337,
            device_id: 0x0001,
            dedicated_video_memory: 256 * 1024 * 1024,
        });
        self.outputs.push(DxgiOutput {
            name: "StrawWU Virtual Monitor 0".into(),
            width: 1920,
            height: 1080,
            refresh_rate_numerator: 60000,
            refresh_rate_denominator: 1000,
            attached_to_adapter: 0,
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

    pub fn enum_outputs(&self) -> Vec<&DxgiOutput> {
        self.outputs.iter().collect()
    }

    pub fn get_adapter_desc(&self, index: usize) -> Option<&DxgiAdapter> {
        self.adapters.get(index)
    }

    pub fn present(&mut self, sync_interval: u32) -> Result<(), DxgiError> {
        if !self.initialized {
            return Err(DxgiError::NotInitialized);
        }
        let _ = sync_interval;
        self.frame_count += 1;
        Ok(())
    }

    pub fn create_swap_chain(&self) -> Result<u64, DxgiError> {
        if !self.initialized {
            return Err(DxgiError::NotInitialized);
        }
        Ok(0x5743_0001)
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

    #[test]
    fn dxgi_enum_outputs() {
        let mut dxgi = DxgiTranslator::new();
        dxgi.create_factory().unwrap();
        let outputs = dxgi.enum_outputs();
        assert_eq!(outputs.len(), 1);
        assert_eq!(outputs[0].width, 1920);
        assert_eq!(outputs[0].height, 1080);
        let hz = outputs[0].refresh_rate_hz();
        assert!((hz - 60.0).abs() < 0.01);
    }

    #[test]
    fn dxgi_get_adapter_desc() {
        let mut dxgi = DxgiTranslator::new();
        dxgi.create_factory().unwrap();
        let adapter = dxgi.get_adapter_desc(0).unwrap();
        assert_eq!(adapter.vendor_id, 0x1337);
        assert!(dxgi.get_adapter_desc(99).is_none());
    }

    #[test]
    fn dxgi_present_increments_frame() {
        let mut dxgi = DxgiTranslator::new();
        dxgi.create_factory().unwrap();
        assert_eq!(dxgi.frame_count, 0);
        dxgi.present(1).unwrap();
        dxgi.present(1).unwrap();
        dxgi.present(0).unwrap();
        assert_eq!(dxgi.frame_count, 3);
    }

    #[test]
    fn dxgi_present_uninit_fails() {
        let mut dxgi = DxgiTranslator::new();
        assert!(dxgi.present(1).is_err());
    }
}
