use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
pub struct AudioBuffer {
    pub samples: Vec<f32>,
    pub channels: u16,
    pub sample_rate: u32,
    pub position: usize,
}

impl AudioBuffer {
    pub fn new(channels: u16, sample_rate: u32) -> Self {
        Self {
            samples: Vec::new(),
            channels,
            sample_rate,
            position: 0,
        }
    }
}

const DEFAULT_BUFFER_SIZE: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WasapiBridge {
    pub backend: AudioBackend,
    pub devices: Vec<AudioDevice>,
    pub initialized: bool,
    pub active_streams: u32,
    volume: f32,
    buffers: HashMap<u32, AudioBuffer>,
    buffer_size: usize,
}

impl WasapiBridge {
    pub fn new(backend: AudioBackend) -> Self {
        Self {
            backend,
            devices: Vec::new(),
            initialized: false,
            active_streams: 0,
            volume: 1.0,
            buffers: HashMap::new(),
            buffer_size: DEFAULT_BUFFER_SIZE,
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
        let sid = self.active_streams;
        self.buffers.insert(sid, AudioBuffer::new(2, 48000));
        Ok(sid)
    }

    pub fn release_stream(&mut self, stream_id: u32) -> Result<(), AudioError> {
        if self.active_streams > 0 {
            self.active_streams -= 1;
        }
        self.buffers.remove(&stream_id);
        Ok(())
    }

    pub fn write_buffer(&mut self, stream_id: u32, samples: &[f32]) -> Result<usize, AudioError> {
        let buf = self.buffers.get_mut(&stream_id).ok_or(AudioError::StreamNotFound)?;
        let available = self.buffer_size.saturating_sub(buf.samples.len());
        let to_write = samples.len().min(available);
        buf.samples.extend_from_slice(&samples[..to_write]);
        Ok(to_write)
    }

    pub fn read_buffer(&mut self, stream_id: u32, max_samples: usize) -> Result<Vec<f32>, AudioError> {
        let buf = self.buffers.get_mut(&stream_id).ok_or(AudioError::StreamNotFound)?;
        let read_count = max_samples.min(buf.samples.len() - buf.position);
        let data = buf.samples[buf.position..buf.position + read_count].to_vec();
        buf.position += read_count;
        Ok(data)
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
    }

    pub fn get_volume(&self) -> f32 {
        self.volume
    }

    pub fn is_format_supported(&self, sample_rate: u32, channels: u16, bits: u16) -> bool {
        let valid_rates = [8000, 11025, 16000, 22050, 44100, 48000, 88200, 96000, 176400, 192000];
        let valid_bits = [8, 16, 24, 32];
        valid_rates.contains(&sample_rate) && channels >= 1 && channels <= 8 && valid_bits.contains(&bits)
    }

    pub fn get_buffer_size(&self) -> usize {
        self.buffer_size
    }

    pub fn get_latency_ms(&self) -> f32 {
        (self.buffer_size as f32 / 48000.0) * 1000.0
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
    #[error("stream not found")]
    StreamNotFound,
    #[error("buffer overflow")]
    BufferOverflow,
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

    #[test]
    fn wasapi_write_and_read_buffer() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        let samples: Vec<f32> = (0..100).map(|i| i as f32 * 0.01).collect();
        let written = bridge.write_buffer(sid, &samples).unwrap();
        assert_eq!(written, 100);
        let read = bridge.read_buffer(sid, 50).unwrap();
        assert_eq!(read.len(), 50);
        assert!((read[0] - 0.0).abs() < f32::EPSILON);
        assert!((read[49] - 0.49).abs() < f32::EPSILON);
    }

    #[test]
    fn wasapi_read_buffer_advances_position() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        let samples = vec![1.0, 2.0, 3.0, 4.0];
        bridge.write_buffer(sid, &samples).unwrap();
        let first = bridge.read_buffer(sid, 2).unwrap();
        assert_eq!(first, vec![1.0, 2.0]);
        let second = bridge.read_buffer(sid, 2).unwrap();
        assert_eq!(second, vec![3.0, 4.0]);
        let empty = bridge.read_buffer(sid, 10).unwrap();
        assert!(empty.is_empty());
    }

    #[test]
    fn wasapi_write_buffer_invalid_stream() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        assert!(bridge.write_buffer(999, &[1.0]).is_err());
    }

    #[test]
    fn wasapi_volume_control() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        assert!((bridge.get_volume() - 1.0).abs() < f32::EPSILON);
        bridge.set_volume(0.5);
        assert!((bridge.get_volume() - 0.5).abs() < f32::EPSILON);
        bridge.set_volume(1.5);
        assert!((bridge.get_volume() - 1.0).abs() < f32::EPSILON);
        bridge.set_volume(-0.5);
        assert!((bridge.get_volume() - 0.0).abs() < f32::EPSILON);
    }

    #[test]
    fn wasapi_format_supported() {
        let bridge = WasapiBridge::new(AudioBackend::PipeWire);
        assert!(bridge.is_format_supported(48000, 2, 16));
        assert!(bridge.is_format_supported(44100, 2, 24));
        assert!(bridge.is_format_supported(96000, 1, 32));
        assert!(!bridge.is_format_supported(12345, 2, 16));
        assert!(!bridge.is_format_supported(48000, 0, 16));
        assert!(!bridge.is_format_supported(48000, 2, 12));
    }

    #[test]
    fn wasapi_buffer_size_and_latency() {
        let bridge = WasapiBridge::new(AudioBackend::PipeWire);
        assert_eq!(bridge.get_buffer_size(), DEFAULT_BUFFER_SIZE);
        let latency = bridge.get_latency_ms();
        assert!(latency > 0.0);
        let expected = (DEFAULT_BUFFER_SIZE as f32 / 48000.0) * 1000.0;
        assert!((latency - expected).abs() < 0.001);
    }

    #[test]
    fn wasapi_write_buffer_respects_capacity() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        let big: Vec<f32> = vec![0.5; DEFAULT_BUFFER_SIZE + 100];
        let written = bridge.write_buffer(sid, &big).unwrap();
        assert_eq!(written, DEFAULT_BUFFER_SIZE);
    }

    #[test]
    fn wasapi_release_removes_buffer() {
        let mut bridge = WasapiBridge::new(AudioBackend::PipeWire);
        bridge.initialize().unwrap();
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        bridge.write_buffer(sid, &[1.0, 2.0]).unwrap();
        bridge.release_stream(sid).unwrap();
        assert!(bridge.read_buffer(sid, 10).is_err());
    }
}
