use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioBackend {
    PipeWire,
    PulseAudio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioFlow {
    Render,
    Capture,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDevice {
    pub name: String,
    pub flow: AudioFlow,
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WasapiBridge {
    pub backend: AudioBackend,
    pub devices: Vec<AudioDevice>,
    pub initialized: bool,
    pub active_streams: u32,
}

impl WasapiBridge {
    pub fn new(backend: AudioBackend) -> Self {
        Self {
            backend,
            devices: Vec::new(),
            initialized: false,
            active_streams: 0,
        }
    }

    pub fn initialize(&mut self) -> Result<(), AudioError> {
        self.devices.push(AudioDevice {
            name: "StrawWU Default Render".into(),
            flow: AudioFlow::Render,
            sample_rate: 48000,
            channels: 2,
            bits_per_sample: 16,
        });
        self.devices.push(AudioDevice {
            name: "StrawWU Default Capture".into(),
            flow: AudioFlow::Capture,
            sample_rate: 48000,
            channels: 1,
            bits_per_sample: 16,
        });
        self.initialized = true;
        Ok(())
    }

    pub fn enumerate_devices(&self, flow: AudioFlow) -> Vec<&AudioDevice> {
        self.devices.iter().filter(|d| d.flow == flow).collect()
    }

    pub fn create_stream(&mut self, _flow: AudioFlow) -> Result<u32, AudioError> {
        if !self.initialized {
            return Err(AudioError::NotInitialized);
        }
        self.active_streams += 1;
        Ok(self.active_streams)
    }

    pub fn release_stream(&mut self, _stream_id: u32) -> Result<(), AudioError> {
        if self.active_streams > 0 {
            self.active_streams -= 1;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum AudioError {
    #[error("WASAPI bridge not initialized")]
    NotInitialized,
    #[error("audio device not found")]
    DeviceNotFound,
    #[error("stream creation failed")]
    StreamFailed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wasapi_init() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        assert!(!bridge.initialized);
        bridge.initialize().unwrap();
        assert!(bridge.initialized);
    }

    #[test]
    fn wasapi_enumerate() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let render = bridge.enumerate_devices(AudioFlow::Render);
        assert_eq!(render.len(), 1);
        let capture = bridge.enumerate_devices(AudioFlow::Capture);
        assert_eq!(capture.len(), 1);
    }

    #[test]
    fn wasapi_stream_lifecycle() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        assert_eq!(bridge.active_streams, 1);
        bridge.release_stream(sid).unwrap();
        assert_eq!(bridge.active_streams, 0);
    }

    #[test]
    fn wasapi_uninit_fails() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        assert!(bridge.create_stream(AudioFlow::Render).is_err());
    }
}
