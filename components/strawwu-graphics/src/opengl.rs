use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GlBackend {
    Glx,
    Egl,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct WglContext(pub u64);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlState {
    pub clear_color: [f32; 4],
    pub viewport: (i32, i32, u32, u32),
    pub depth_test: bool,
    pub blend: bool,
    pub cull_face: bool,
    pub active_texture_unit: u32,
    pub current_program: u64,
    pub bound_vao: u64,
    pub bound_vbo: u64,
    pub bound_framebuffer: u64,
}

impl Default for GlState {
    fn default() -> Self {
        Self {
            clear_color: [0.0, 0.0, 0.0, 1.0],
            viewport: (0, 0, 800, 600),
            depth_test: false,
            blend: false,
            cull_face: false,
            active_texture_unit: 0,
            current_program: 0,
            bound_vao: 0,
            bound_vbo: 0,
            bound_framebuffer: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WglBridge {
    pub backend: GlBackend,
    pub gl_version: String,
    pub gl_renderer: String,
    pub gl_vendor: String,
    pub glsl_version: String,
    pub initialized: bool,
    pub supported_extensions: Vec<String>,
    contexts: HashMap<u64, GlState>,
    current_context: Option<u64>,
    next_context_id: u64,
    next_object_id: u64,
    frame_count: u64,
}

impl WglBridge {
    pub fn new(backend: GlBackend) -> Self {
        Self {
            backend,
            gl_version: "4.6 StrawWU".into(),
            gl_renderer: "StrawWU OpenGL Passthrough".into(),
            gl_vendor: "StrawWU Project".into(),
            glsl_version: "460".into(),
            initialized: false,
            supported_extensions: vec![
                "GL_ARB_vertex_buffer_object".into(),
                "GL_ARB_shader_objects".into(),
                "GL_ARB_fragment_shader".into(),
                "GL_ARB_vertex_shader".into(),
                "GL_ARB_texture_non_power_of_two".into(),
                "GL_ARB_framebuffer_object".into(),
                "GL_ARB_vertex_array_object".into(),
                "GL_ARB_uniform_buffer_object".into(),
                "GL_ARB_instanced_arrays".into(),
                "GL_ARB_compute_shader".into(),
                "GL_ARB_tessellation_shader".into(),
                "GL_ARB_direct_state_access".into(),
            ],
            contexts: HashMap::new(),
            current_context: None,
            next_context_id: 0x1000,
            next_object_id: 0x0100,
            frame_count: 0,
        }
    }

    pub fn wgl_create_context(&mut self) -> Result<WglContext, WglError> {
        let id = self.next_context_id;
        self.next_context_id += 1;
        self.contexts.insert(id, GlState::default());
        self.initialized = true;
        Ok(WglContext(id))
    }

    pub fn wgl_make_current(&mut self, context: WglContext) -> Result<(), WglError> {
        if !self.contexts.contains_key(&context.0) {
            return Err(WglError::InvalidContext);
        }
        self.current_context = Some(context.0);
        Ok(())
    }

    pub fn wgl_delete_context(&mut self, context: WglContext) -> Result<(), WglError> {
        if self.contexts.remove(&context.0).is_none() {
            return Err(WglError::InvalidContext);
        }
        if self.current_context == Some(context.0) {
            self.current_context = None;
        }
        Ok(())
    }

    pub fn wgl_get_proc_address(&self, name: &str) -> Option<u64> {
        let known_functions = [
            "glGenBuffers", "glBindBuffer", "glBufferData", "glBufferSubData",
            "glCreateShader", "glShaderSource", "glCompileShader", "glDeleteShader",
            "glCreateProgram", "glAttachShader", "glLinkProgram", "glDeleteProgram",
            "glUseProgram", "glGetUniformLocation", "glUniform1f", "glUniform1i",
            "glUniform3f", "glUniform4f", "glUniformMatrix4fv",
            "glGenVertexArrays", "glBindVertexArray", "glDeleteVertexArrays",
            "glVertexAttribPointer", "glEnableVertexAttribArray",
            "glGenTextures", "glBindTexture", "glTexImage2D", "glTexParameteri",
            "glActiveTexture", "glGenerateMipmap",
            "glGenFramebuffers", "glBindFramebuffer", "glFramebufferTexture2D",
            "glCheckFramebufferStatus", "glDeleteFramebuffers",
            "glDrawArrays", "glDrawElements", "glDrawArraysInstanced",
            "glClear", "glClearColor", "glEnable", "glDisable",
            "glViewport", "glScissor", "glBlendFunc", "glDepthFunc",
            "glGetString", "glGetIntegerv", "glGetError",
        ];
        if known_functions.contains(&name) {
            Some(0xDE00_0000 + name.len() as u64)
        } else {
            None
        }
    }

    pub fn wgl_swap_buffers(&mut self) -> Result<(), WglError> {
        if self.current_context.is_none() {
            return Err(WglError::NotInitialized);
        }
        self.frame_count += 1;
        Ok(())
    }

    // GL state operations (applied to current context)

    pub fn gl_clear_color(&mut self, r: f32, g: f32, b: f32, a: f32) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        state.clear_color = [r, g, b, a];
        Ok(())
    }

    pub fn gl_viewport(&mut self, x: i32, y: i32, w: u32, h: u32) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        state.viewport = (x, y, w, h);
        Ok(())
    }

    pub fn gl_enable(&mut self, cap: u32) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        match cap {
            0x0B71 => state.depth_test = true,  // GL_DEPTH_TEST
            0x0BE2 => state.blend = true,       // GL_BLEND
            0x0B44 => state.cull_face = true,   // GL_CULL_FACE
            _ => {}
        }
        Ok(())
    }

    pub fn gl_disable(&mut self, cap: u32) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        match cap {
            0x0B71 => state.depth_test = false,
            0x0BE2 => state.blend = false,
            0x0B44 => state.cull_face = false,
            _ => {}
        }
        Ok(())
    }

    pub fn gl_use_program(&mut self, program: u64) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        state.current_program = program;
        Ok(())
    }

    pub fn gl_bind_vertex_array(&mut self, vao: u64) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        state.bound_vao = vao;
        Ok(())
    }

    pub fn gl_bind_framebuffer(&mut self, fbo: u64) -> Result<(), WglError> {
        let state = self.current_state_mut()?;
        state.bound_framebuffer = fbo;
        Ok(())
    }

    pub fn gen_object(&mut self) -> u64 {
        let id = self.next_object_id;
        self.next_object_id += 1;
        id
    }

    pub fn context_count(&self) -> usize {
        self.contexts.len()
    }

    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }

    pub fn current_state(&self) -> Option<&GlState> {
        self.current_context.and_then(|id| self.contexts.get(&id))
    }

    fn current_state_mut(&mut self) -> Result<&mut GlState, WglError> {
        let id = self.current_context.ok_or(WglError::NotInitialized)?;
        self.contexts.get_mut(&id).ok_or(WglError::InvalidContext)
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
    fn wgl_full_pipeline() {
        let mut bridge = WglBridge::new(GlBackend::Egl);

        // Create and activate context
        let ctx = bridge.wgl_create_context().unwrap();
        bridge.wgl_make_current(ctx).unwrap();
        assert!(bridge.initialized);

        // Set GL state
        bridge.gl_clear_color(0.2, 0.3, 0.3, 1.0).unwrap();
        bridge.gl_viewport(0, 0, 1920, 1080).unwrap();
        bridge.gl_enable(0x0B71).unwrap(); // depth test

        let state = bridge.current_state().unwrap();
        assert_eq!(state.clear_color, [0.2, 0.3, 0.3, 1.0]);
        assert_eq!(state.viewport, (0, 0, 1920, 1080));
        assert!(state.depth_test);

        // Generate objects
        let vao = bridge.gen_object();
        bridge.gl_bind_vertex_array(vao).unwrap();
        assert_eq!(bridge.current_state().unwrap().bound_vao, vao);

        let program = bridge.gen_object();
        bridge.gl_use_program(program).unwrap();
        assert_eq!(bridge.current_state().unwrap().current_program, program);

        // Render frames
        for _ in 0..10 {
            bridge.wgl_swap_buffers().unwrap();
        }
        assert_eq!(bridge.frame_count(), 10);
    }

    #[test]
    fn wgl_create_context() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        let ctx = bridge.wgl_create_context().unwrap();
        assert!(ctx.0 != 0);
        assert!(bridge.initialized);
    }

    #[test]
    fn wgl_multiple_contexts() {
        let mut bridge = WglBridge::new(GlBackend::Glx);
        let c1 = bridge.wgl_create_context().unwrap();
        let c2 = bridge.wgl_create_context().unwrap();
        assert_ne!(c1.0, c2.0);
        assert_eq!(bridge.context_count(), 2);

        bridge.wgl_delete_context(c1).unwrap();
        assert_eq!(bridge.context_count(), 1);
    }

    #[test]
    fn wgl_make_current_invalid() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.wgl_make_current(WglContext(0xDEAD)).is_err());
    }

    #[test]
    fn wgl_get_proc() {
        let bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.wgl_get_proc_address("glGenBuffers").is_some());
        assert!(bridge.wgl_get_proc_address("glDrawArrays").is_some());
        assert!(bridge.wgl_get_proc_address("glGenFramebuffers").is_some());
        assert!(bridge.wgl_get_proc_address("glNonexistent").is_none());
    }

    #[test]
    fn wgl_swap_buffers_no_context() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.wgl_swap_buffers().is_err());
    }

    #[test]
    fn wgl_swap_buffers() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        let ctx = bridge.wgl_create_context().unwrap();
        bridge.wgl_make_current(ctx).unwrap();
        assert!(bridge.wgl_swap_buffers().is_ok());
    }

    #[test]
    fn gl_version_info() {
        let bridge = WglBridge::new(GlBackend::Egl);
        assert!(bridge.gl_version.contains("StrawWU"));
        assert!(bridge.glsl_version.contains("460"));
        assert!(!bridge.supported_extensions.is_empty());
        assert!(bridge.supported_extensions.len() >= 10);
    }

    #[test]
    fn gl_state_enable_disable() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        let ctx = bridge.wgl_create_context().unwrap();
        bridge.wgl_make_current(ctx).unwrap();

        bridge.gl_enable(0x0BE2).unwrap(); // BLEND
        assert!(bridge.current_state().unwrap().blend);
        bridge.gl_disable(0x0BE2).unwrap();
        assert!(!bridge.current_state().unwrap().blend);
    }

    #[test]
    fn gl_framebuffer_binding() {
        let mut bridge = WglBridge::new(GlBackend::Egl);
        let ctx = bridge.wgl_create_context().unwrap();
        bridge.wgl_make_current(ctx).unwrap();

        let fbo = bridge.gen_object();
        bridge.gl_bind_framebuffer(fbo).unwrap();
        assert_eq!(bridge.current_state().unwrap().bound_framebuffer, fbo);

        bridge.gl_bind_framebuffer(0).unwrap();
        assert_eq!(bridge.current_state().unwrap().bound_framebuffer, 0);
    }
}
