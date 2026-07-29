use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::f32::consts::PI;
use std::io::Write;
use std::path::Path;

use crate::host::{HostAudioKind, HostAudioProbe};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioBackend {
    PipeWire,
    PulseAudio,
    Alsa,
    File,
}

impl From<HostAudioKind> for AudioBackend {
    fn from(kind: HostAudioKind) -> Self {
        match kind {
            HostAudioKind::PipeWire => Self::PipeWire,
            HostAudioKind::PulseAudio => Self::PulseAudio,
            HostAudioKind::Alsa => Self::Alsa,
            HostAudioKind::File => Self::File,
        }
    }
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
    pub host: HostAudioProbe,
    /// Total float samples accepted via write_buffer (observability).
    pub samples_written: u64,
    /// Bytes written to host/file render sinks.
    pub bytes_rendered: u64,
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
            host: HostAudioProbe::probe(),
            samples_written: 0,
            bytes_rendered: 0,
            volume: 1.0,
            buffers: HashMap::new(),
            buffer_size: DEFAULT_BUFFER_SIZE,
        }
    }

    /// Prefer host-probed backend (PipeWire → Pulse → ALSA → File).
    pub fn from_host() -> Self {
        let host = HostAudioProbe::probe();
        let backend = AudioBackend::from(host.selected);
        let mut bridge = Self::new(backend);
        bridge.host = host;
        bridge
    }

    pub fn initialize(&mut self) -> Result<(), AudioError> {
        let render_name = match self.backend {
            AudioBackend::PipeWire => "StrawWU PipeWire Render",
            AudioBackend::PulseAudio => "StrawWU PulseAudio Render",
            AudioBackend::Alsa => "StrawWU ALSA Render",
            AudioBackend::File => "StrawWU File Render",
        };
        self.devices.push(AudioDevice {
            name: render_name.into(),
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
        // Surface host ALSA nodes as extra render devices when present.
        for node in self.host.alsa_pcm_devices.iter().filter(|n| n.starts_with("pcm") && n.ends_with('p')) {
            self.devices.push(AudioDevice {
                name: format!("ALSA {node}"),
                flow: AudioFlow::Render,
                sample_rate: 48000,
                channels: 2,
                bits_per_sample: 16,
            });
        }
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
        self.samples_written += to_write as u64;
        Ok(to_write)
    }

    /// Generate a mono/stereo sine tone into `out` (interleaved if stereo).
    pub fn generate_tone(
        frequency_hz: f32,
        duration_secs: f32,
        sample_rate: u32,
        channels: u16,
        amplitude: f32,
    ) -> Vec<f32> {
        let frames = (duration_secs * sample_rate as f32).round() as usize;
        let mut out = Vec::with_capacity(frames * channels as usize);
        for i in 0..frames {
            let t = i as f32 / sample_rate as f32;
            let sample = (2.0 * PI * frequency_hz * t).sin() * amplitude;
            for _ in 0..channels {
                out.push(sample);
            }
        }
        out
    }

    /// Render stream buffer (or provided samples) to a 16-bit PCM WAV file.
    /// This is the observable WASAPI→host side effect when a real SPA client is unavailable.
    pub fn render_wav(
        &mut self,
        stream_id: u32,
        path: &Path,
        sample_rate: u32,
        channels: u16,
    ) -> Result<usize, AudioError> {
        let samples = {
            let buf = self.buffers.get(&stream_id).ok_or(AudioError::StreamNotFound)?;
            if buf.samples.is_empty() {
                return Err(AudioError::EmptyBuffer);
            }
            buf.samples.clone()
        };
        let bytes = write_wav_i16(path, &samples, sample_rate, channels)?;
        self.bytes_rendered += bytes as u64;
        Ok(bytes)
    }

    /// Write float samples directly as WAV (bypasses ring capacity for evidence dumps).
    pub fn render_samples_wav(
        &mut self,
        path: &Path,
        samples: &[f32],
        sample_rate: u32,
        channels: u16,
    ) -> Result<usize, AudioError> {
        if samples.is_empty() {
            return Err(AudioError::EmptyBuffer);
        }
        let bytes = write_wav_i16(path, samples, sample_rate, channels)?;
        self.bytes_rendered += bytes as u64;
        self.samples_written += samples.len() as u64;
        Ok(bytes)
    }

    pub fn read_buffer(&mut self, stream_id: u32, max_samples: usize) -> Result<Vec<f32>, AudioError> {
        let buf = self.buffers.get_mut(&stream_id).ok_or(AudioError::StreamNotFound)?;
        let available = buf.samples.len().saturating_sub(buf.position);
        let read_count = max_samples.min(available);
        let start = buf.position;
        let data = buf.samples[start..start + read_count].to_vec();
        // Drain consumed samples so the ring can accept more writes.
        buf.samples.drain(0..start + read_count);
        buf.position = 0;
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
    #[error("empty audio buffer")]
    EmptyBuffer,
    #[error("io: {0}")]
    Io(String),
}

/// Write interleaved f32 samples as little-endian 16-bit PCM WAV.
pub fn write_wav_i16(
    path: &Path,
    samples: &[f32],
    sample_rate: u32,
    channels: u16,
) -> Result<usize, AudioError> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| AudioError::Io(e.to_string()))?;
    }
    let mut pcm = Vec::with_capacity(samples.len() * 2);
    for &s in samples {
        let v = (s.clamp(-1.0, 1.0) * 32767.0).round() as i16;
        pcm.extend_from_slice(&v.to_le_bytes());
    }
    let data_len = pcm.len() as u32;
    let byte_rate = sample_rate * channels as u32 * 2;
    let block_align = channels * 2;
    let mut out = Vec::with_capacity(44 + pcm.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&channels.to_le_bytes());
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&byte_rate.to_le_bytes());
    out.extend_from_slice(&block_align.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    out.extend_from_slice(&pcm);
    let mut file = std::fs::File::create(path).map_err(|e| AudioError::Io(e.to_string()))?;
    file.write_all(&out).map_err(|e| AudioError::Io(e.to_string()))?;
    Ok(out.len())
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
        assert!(!render.is_empty());
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

    #[test]
    fn wasapi_tone_and_wav_side_effect() {
        let mut bridge = WasapiBridge::from_host();
        bridge.initialize().unwrap();
        let tone = WasapiBridge::generate_tone(440.0, 0.05, 48000, 2, 0.25);
        assert!(tone.len() > 1000);
        let sid = bridge.create_stream(AudioFlow::Render).unwrap();
        // Feed in chunks respecting ring capacity.
        let mut offset = 0;
        while offset < tone.len() {
            let end = (offset + DEFAULT_BUFFER_SIZE).min(tone.len());
            let written = bridge.write_buffer(sid, &tone[offset..end]).unwrap();
            assert!(written > 0);
            // Drain so more can be written.
            let _ = bridge.read_buffer(sid, written).unwrap();
            offset += written;
        }
        let dir = std::env::temp_dir().join(format!(
            "strawwu-wasapi-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("tone.wav");
        let bytes = bridge
            .render_samples_wav(&wav, &tone, 48000, 2)
            .unwrap();
        assert!(bytes > 44);
        let data = std::fs::read(&wav).unwrap();
        assert!(data.starts_with(b"RIFF"));
        assert!(data[8..12] == *b"WAVE");
        assert!(bridge.bytes_rendered > 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn wasapi_from_host_selects_backend() {
        let bridge = WasapiBridge::from_host();
        match bridge.backend {
            AudioBackend::PipeWire
            | AudioBackend::PulseAudio
            | AudioBackend::Alsa
            | AudioBackend::File => {}
        }
    }
}
