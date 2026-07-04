use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GlBackend {
    Glx,
    Egl,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WglBridge {
    pub backend: GlBackend,
    pub gl_version: String,
    pub gl_renderer: String,
    pub gl_vendor: String,
    pub initialized: bool,
    pub supported_extensions: Vec<String>,
}

impl WglBridge {
    pub fn new(backend: GlBackend) -> Self {
        Self {
            backend,
            gl_version: "2.1 StrawWU".into(),
            gl_renderer: "StrawWU OpenGL Passthrough".into(),
            gl_vendor: "StrawWU Project".into(),
            initialized: false,
            supported_extensions: vec![
                "GL_ARB_vertex_buffer_object".into(),
                "GL_ARB_shader_objects".into(),
                "GL_ARB_fragment_shader".into(),
                "GL_ARB_vertex_shader".into(),
                "GL_ARB_texture_non_power_of_two".into(),
            ],
        }
    }

    pub fn wgl_create_context(&mut self) -> Result<u64, WglError> {
        self.initialized = true;
        Ok(0x1000)
    }

    pub fn wgl_make_current(&self, context: u64) -> Result<(), WglError> {
        if !self.initialized {
            return Err(WglError::NotInitialized);
        }
        if context == 0 {
            return Err(WglError::InvalidContext);
        }
        Ok(())
    }

    pub fn wgl_get_proc_address(&self, name: &str) -> Option<u64> {
        match name {
            "glGenBuffers" | "glBindBuffer" | "glBufferData" |
            "glCreateShader" | "glShaderSource" | "glCompileShader" |
            "glCreateProgram" | "glAttachShader" | "glLinkProgram" |
            "glUseProgram" | "glGetUniformLocation" => Some(0xDEAD_0000),
            _ => None,
        }
    }

    pub fn wgl_swap_buffers(&self) -> Result<(), WglError> {
        if !self.initialized {
            return Err(WglError::NotInitialized);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum WglError {
    #[error("WGL context not initialized")]
    NotInitialized,
    #[error("invalid WGL context handle")]
    InvalidContext,
    #[error("function not supported")]
    NotSupported,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wgl_create_context() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        let ctx = bridge.wgl_create_context().unwrap();
        assert!(ctx != 0);
        assert!(bridge.initialized);
    }

    #[test]
    fn wgl_make_current() {
        let mut bridge = WglBridge::new(GlBackend::Glx);
        let ctx = bridge.wgl_create_context().unwrap();
        assert!(bridge.wgl_make_current(ctx).is_ok());
    }

    #[test]
    fn wgl_make_current_uninit_fails() {
        let bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.wgl_make_current(0x1000).is_err());
    }

    #[test]
    fn wgl_get_proc() {
        let bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.wgl_get_proc_address("glGenBuffers").is_some());
        assert!(bridge.wgl_get_proc_address("glNonexistent").is_none());
    }

    #[test]
    fn wgl_swap_buffers() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        bridge.wgl_create_context().unwrap();
        assert!(bridge.wgl_swap_buffers().is_ok());
    }

    #[test]
    fn gl_version_info() {
        let bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.gl_version.contains("StrawWU"));
        assert!(!bridge.supported_extensions.is_empty());
    }
}
