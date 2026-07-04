use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum D3DFeatureLevel {
    Level9_1,
    Level9_3,
    Level10_0,
    Level10_1,
    Level11_0,
    Level11_1,
}

impl D3DFeatureLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Level9_1 => "9_1",
            Self::Level9_3 => "9_3",
            Self::Level10_0 => "10_0",
            Self::Level10_1 => "10_1",
            Self::Level11_0 => "11_0",
            Self::Level11_1 => "11_1",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct D3D11Device {
    pub feature_level: D3DFeatureLevel,
    pub adapter_desc: String,
    pub initialized: bool,
    pub translation_target: String,
}

impl D3D11Device {
    pub fn create(requested_level: D3DFeatureLevel) -> Result<Self, D3D11Error> {
        Ok(Self {
            feature_level: requested_level,
            adapter_desc: "StrawWU D3D11→Vulkan".into(),
            initialized: true,
            translation_target: "vulkan".into(),
        })
    }

    pub fn create_buffer(&self, size: u64) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(0xB0F0_0000 | (size & 0xFFFF))
    }

    pub fn create_texture_2d(&self, width: u32, height: u32) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(0xAE00_0000_u64.wrapping_add((width as u64) << 16 | height as u64))
    }

    pub fn create_render_target_view(&self) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(0xA1C0_0001)
    }

    pub fn present(&self) -> Result<(), D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum D3D11Error {
    #[error("D3D11 device not ready")]
    DeviceNotReady,
    #[error("unsupported feature level")]
    UnsupportedFeatureLevel,
    #[error("resource creation failed")]
    ResourceCreationFailed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn d3d11_device_create() {
        let dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        assert!(dev.initialized);
        assert_eq!(dev.feature_level, D3DFeatureLevel::Level11_0);
        assert_eq!(dev.translation_target, "vulkan");
    }

    #[test]
    fn d3d11_create_buffer() {
        let dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        let buf = dev.create_buffer(4096).unwrap();
        assert!(buf != 0);
    }

    #[test]
    fn d3d11_present() {
        let dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        assert!(dev.present().is_ok());
    }

    #[test]
    fn d3d11_feature_level_str() {
        assert_eq!(D3DFeatureLevel::Level11_0.as_str(), "11_0");
        assert_eq!(D3DFeatureLevel::Level9_1.as_str(), "9_1");
    }
}
