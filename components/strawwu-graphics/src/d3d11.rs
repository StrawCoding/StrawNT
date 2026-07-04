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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ShaderType {
    Vertex,
    Pixel,
    Geometry,
    Hull,
    Domain,
    Compute,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ResourceKind {
    Buffer,
    Texture2D,
    RenderTargetView,
    Shader,
    InputLayout,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct D3D11Resource {
    pub handle: u64,
    pub kind: ResourceKind,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DxgiFormat {
    R32G32B32Float,
    R32G32Float,
    R8G8B8A8Unorm,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputElement {
    pub semantic_name: String,
    pub semantic_index: u32,
    pub format: DxgiFormat,
    pub input_slot: u32,
    pub byte_offset: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct D3D11Device {
    pub feature_level: D3DFeatureLevel,
    pub adapter_desc: String,
    pub initialized: bool,
    pub translation_target: String,
    pub resources: Vec<D3D11Resource>,
    pub draw_calls: u64,
    pub triangles_drawn: u64,
    next_handle: u64,
}

impl D3D11Device {
    pub fn create(requested_level: D3DFeatureLevel) -> Result<Self, D3D11Error> {
        Ok(Self {
            feature_level: requested_level,
            adapter_desc: "StrawWU D3D11→Vulkan".into(),
            initialized: true,
            translation_target: "vulkan".into(),
            resources: Vec::new(),
            draw_calls: 0,
            triangles_drawn: 0,
            next_handle: 1,
        })
    }

    fn alloc_handle(&mut self) -> u64 {
        let h = self.next_handle;
        self.next_handle += 1;
        h
    }

    fn track(&mut self, kind: ResourceKind, size_bytes: u64) -> u64 {
        let handle = self.alloc_handle();
        self.resources.push(D3D11Resource {
            handle,
            kind,
            size_bytes,
        });
        handle
    }

    pub fn create_buffer(&mut self, size: u64) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(self.track(ResourceKind::Buffer, size))
    }

    pub fn create_texture_2d(&mut self, width: u32, height: u32) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        let size = width as u64 * height as u64 * 4;
        Ok(self.track(ResourceKind::Texture2D, size))
    }

    pub fn create_render_target_view(&mut self) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(self.track(ResourceKind::RenderTargetView, 0))
    }

    pub fn create_shader(&mut self, shader_type: ShaderType, source_hash: u64) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        let _ = shader_type;
        let _ = source_hash;
        Ok(self.track(ResourceKind::Shader, 0))
    }

    pub fn create_input_layout(&mut self, elements: &[InputElement]) -> Result<u64, D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        if elements.is_empty() {
            return Err(D3D11Error::ResourceCreationFailed);
        }
        Ok(self.track(ResourceKind::InputLayout, 0))
    }

    pub fn draw(&mut self, vertex_count: u32, _start: u32) -> Result<(), D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        self.draw_calls += 1;
        self.triangles_drawn += vertex_count as u64 / 3;
        Ok(())
    }

    pub fn clear_render_target(&mut self, rtv: u64, color: [f32; 4]) -> Result<(), D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        let exists = self.resources.iter().any(|r| {
            r.handle == rtv && r.kind == ResourceKind::RenderTargetView
        });
        if !exists {
            return Err(D3D11Error::ResourceCreationFailed);
        }
        for c in &color {
            if c.is_nan() || c.is_infinite() {
                return Err(D3D11Error::InvalidArgument);
            }
        }
        Ok(())
    }

    pub fn present(&self) -> Result<(), D3D11Error> {
        if !self.initialized {
            return Err(D3D11Error::DeviceNotReady);
        }
        Ok(())
    }

    pub fn resource_count(&self) -> usize {
        self.resources.len()
    }

    pub fn resources_by_kind(&self, kind: ResourceKind) -> Vec<&D3D11Resource> {
        self.resources.iter().filter(|r| r.kind == kind).collect()
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
    #[error("invalid argument")]
    InvalidArgument,
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
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
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

    #[test]
    fn d3d11_resource_tracking_buffer() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        dev.create_buffer(1024).unwrap();
        dev.create_buffer(2048).unwrap();
        assert_eq!(dev.resource_count(), 2);
        let bufs = dev.resources_by_kind(ResourceKind::Buffer);
        assert_eq!(bufs.len(), 2);
        assert_eq!(bufs[0].size_bytes, 1024);
        assert_eq!(bufs[1].size_bytes, 2048);
    }

    #[test]
    fn d3d11_resource_tracking_mixed() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        dev.create_buffer(512).unwrap();
        dev.create_texture_2d(256, 256).unwrap();
        dev.create_render_target_view().unwrap();
        assert_eq!(dev.resource_count(), 3);
        assert_eq!(dev.resources_by_kind(ResourceKind::Buffer).len(), 1);
        assert_eq!(dev.resources_by_kind(ResourceKind::Texture2D).len(), 1);
        assert_eq!(dev.resources_by_kind(ResourceKind::RenderTargetView).len(), 1);
    }

    #[test]
    fn d3d11_create_shader() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        let vs = dev.create_shader(ShaderType::Vertex, 0xDEAD).unwrap();
        let ps = dev.create_shader(ShaderType::Pixel, 0xBEEF).unwrap();
        assert_ne!(vs, ps);
        assert_eq!(dev.resources_by_kind(ResourceKind::Shader).len(), 2);
    }

    #[test]
    fn d3d11_create_input_layout() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        let elems = vec![
            InputElement {
                semantic_name: "POSITION".into(),
                semantic_index: 0,
                format: DxgiFormat::R32G32B32Float,
                input_slot: 0,
                byte_offset: 0,
            },
            InputElement {
                semantic_name: "TEXCOORD".into(),
                semantic_index: 0,
                format: DxgiFormat::R32G32Float,
                input_slot: 0,
                byte_offset: 12,
            },
        ];
        let handle = dev.create_input_layout(&elems).unwrap();
        assert!(handle > 0);
        assert_eq!(dev.resources_by_kind(ResourceKind::InputLayout).len(), 1);
    }

    #[test]
    fn d3d11_create_input_layout_empty_fails() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        assert!(dev.create_input_layout(&[]).is_err());
    }

    #[test]
    fn d3d11_draw_increments_stats() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        dev.draw(6, 0).unwrap();
        dev.draw(3, 0).unwrap();
        assert_eq!(dev.draw_calls, 2);
        assert_eq!(dev.triangles_drawn, 3); // 6/3 + 3/3
    }

    #[test]
    fn d3d11_clear_render_target() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        let rtv = dev.create_render_target_view().unwrap();
        assert!(dev.clear_render_target(rtv, [0.0, 0.0, 0.0, 1.0]).is_ok());
    }

    #[test]
    fn d3d11_clear_render_target_invalid_handle() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        assert!(dev.clear_render_target(9999, [0.0, 0.0, 0.0, 1.0]).is_err());
    }

    #[test]
    fn d3d11_unique_handles() {
        let mut dev = D3D11Device::create(D3DFeatureLevel::Level11_0).unwrap();
        let h1 = dev.create_buffer(64).unwrap();
        let h2 = dev.create_buffer(128).unwrap();
        let h3 = dev.create_texture_2d(64, 64).unwrap();
        let h4 = dev.create_shader(ShaderType::Vertex, 1).unwrap();
        let handles = vec![h1, h2, h3, h4];
        for (i, a) in handles.iter().enumerate() {
            for (j, b) in handles.iter().enumerate() {
                if i != j {
                    assert_ne!(a, b);
                }
            }
        }
    }
}
