//! Portable audio/input pipeline: WASAPI → PipeWire (or ALSA/Pulse/File equivalent)
//! plus XInput basic input path. Emits observable WAV + input observation JSON.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::host::HostAudioKind;
use crate::input_path::{run_input_path_smoke, InputPathResult};
use crate::wasapi::{AudioBackend, AudioFlow, WasapiBridge};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathEvidence {
    pub name: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioInputSmokeResult {
    pub status: String,
    pub backend: String,
    pub execution_backend: String,
    pub host_audio_backend: String,
    pub audio_backend: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub tone_hz: f32,
    pub samples_generated: u64,
    pub samples_written: u64,
    pub bytes_rendered: u64,
    pub streams_created: u32,
    pub devices_render: usize,
    pub devices_capture: usize,
    pub pipewire_socket_present: bool,
    pub alsa_nodes: usize,
    pub input: InputPathSummary,
    pub paths: Vec<PathEvidence>,
    pub gaps: Vec<String>,
    pub wav_path: Option<String>,
    pub input_obs_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputPathSummary {
    pub controllers_connected: usize,
    pub button_events: u32,
    pub axis_events: u32,
    pub vibration_set: bool,
    pub deadzone_applied: bool,
    pub evdev_count: usize,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum PipelineError {
    #[error("wasapi: {0}")]
    Wasapi(String),
    #[error("input: {0}")]
    Input(String),
    #[error("io: {0}")]
    Io(String),
}

const SAMPLE_RATE: u32 = 48_000;
const CHANNELS: u16 = 2;
const TONE_HZ: f32 = 440.0;
const TONE_SECS: f32 = 0.25;
const TONE_AMP: f32 = 0.35;

/// Run full GX1 audio/input smoke and write artifacts under `out_dir`.
pub fn run_audio_input_smoke(out_dir: &Path) -> Result<AudioInputSmokeResult, PipelineError> {
    std::fs::create_dir_all(out_dir).map_err(|e| PipelineError::Io(e.to_string()))?;

    let mut bridge = WasapiBridge::from_host();
    bridge
        .initialize()
        .map_err(|e| PipelineError::Wasapi(e.to_string()))?;

    let sid = bridge
        .create_stream(AudioFlow::Render)
        .map_err(|e| PipelineError::Wasapi(e.to_string()))?;

    let tone = WasapiBridge::generate_tone(TONE_HZ, TONE_SECS, SAMPLE_RATE, CHANNELS, TONE_AMP);
    // Feed ring in chunks (WASAPI-like write path), then dump full tone for evidence.
    let mut fed = 0usize;
    let chunk = bridge.get_buffer_size();
    while fed < tone.len() {
        let end = (fed + chunk).min(tone.len());
        let written = bridge
            .write_buffer(sid, &tone[fed..end])
            .map_err(|e| PipelineError::Wasapi(e.to_string()))?;
        if written == 0 {
            break;
        }
        let _ = bridge
            .read_buffer(sid, written)
            .map_err(|e| PipelineError::Wasapi(e.to_string()))?;
        fed += written;
    }

    let wav_path = out_dir.join("gx-tone.wav");
    let bytes = bridge
        .render_samples_wav(&wav_path, &tone, SAMPLE_RATE, CHANNELS)
        .map_err(|e| PipelineError::Wasapi(e.to_string()))?;

    let input_obs = out_dir.join("gx-input-obs.json");
    let input = run_input_path_smoke(Some(&input_obs))
        .map_err(|e| PipelineError::Input(e.to_string()))?;

    let host_kind = bridge.host.selected;
    let pipewire_socket_present = bridge.host.pipewire_socket.is_some();
    let alsa_nodes = bridge.host.alsa_pcm_devices.len();

    let mut paths = Vec::new();
    paths.push(PathEvidence {
        name: "host_audio_probe".into(),
        status: "PASS".into(),
        detail: format!(
            "selected={} pipewire_socket={} alsa_nodes={} notes={}",
            host_kind.as_str(),
            pipewire_socket_present,
            alsa_nodes,
            bridge.host.notes.len()
        ),
    });
    paths.push(PathEvidence {
        name: "wasapi_stream_lifecycle".into(),
        status: if bridge.initialized && bridge.active_streams >= 1 {
            "PASS".into()
        } else {
            "FAIL".into()
        },
        detail: format!(
            "backend={:?} streams={} devices={}",
            bridge.backend,
            bridge.active_streams,
            bridge.devices.len()
        ),
    });
    paths.push(PathEvidence {
        name: "wasapi_tone_render".into(),
        status: if bytes > 44 && tone.len() > 1000 {
            "PASS".into()
        } else {
            "FAIL".into()
        },
        detail: format!(
            "hz={TONE_HZ} samples={} bytes_wav={bytes} samples_written={}",
            tone.len(),
            bridge.samples_written
        ),
    });
    paths.push(PathEvidence {
        name: "wasapi_to_host_bridge".into(),
        status: if bridge.host.is_pipewire_or_equivalent() {
            "PASS".into()
        } else {
            "FAIL".into()
        },
        detail: format!(
            "wasapi→{} (pipewire_preferred={}, equivalent_ok={})",
            audio_backend_label(bridge.backend),
            matches!(bridge.backend, AudioBackend::PipeWire),
            !matches!(host_kind, HostAudioKind::File) || pipewire_socket_present || alsa_nodes > 0
        ),
    });
    paths.push(PathEvidence {
        name: "xinput_basic_path".into(),
        status: if input.controllers_connected >= 1
            && input.button_events >= 1
            && input.deadzone_applied
            && input.vibration_set
        {
            "PASS".into()
        } else {
            "FAIL".into()
        },
        detail: format!(
            "controllers={} buttons={} axes={} vib={} deadzone={} evdev={}",
            input.controllers_connected,
            input.button_events,
            input.axis_events,
            input.vibration_set,
            input.deadzone_applied,
            input.host.evdev_count
        ),
    });
    paths.push(PathEvidence {
        name: "pcm_wav_evidence".into(),
        status: if wav_path.is_file() {
            "PASS".into()
        } else {
            "FAIL".into()
        },
        detail: format!("wav={}", wav_path.display()),
    });

    let failed: Vec<String> = paths
        .iter()
        .filter(|p| p.status != "PASS")
        .map(|p| p.name.clone())
        .collect();

    let mut gaps = vec![
        "native libpipewire SPA client not linked; host path is probe + PCM file / ALSA-equivalent sink".into(),
        "real Win PE WASAPI/XAudio2 import trampolines not yet hooked in strawwu-nt CPU loop".into(),
        "live microphone capture / exclusive WASAPI mode not exercised in gx1".into(),
        "DirectInput full HID enumeration remains stub-level beyond XInput matrix".into(),
    ];
    if !pipewire_socket_present {
        gaps.push(
            "host PipeWire socket not present; selected ALSA/Pulse/File equivalent backend".into(),
        );
    }

    let status = if failed.is_empty() {
        // Core portable path PASS; remaining items are known limitations.
        "PASS".into()
    } else if failed.len() < paths.len() {
        for f in &failed {
            gaps.push(format!("check_failed:{f}"));
        }
        "PARTIAL".into()
    } else {
        for f in &failed {
            gaps.push(format!("check_failed:{f}"));
        }
        "FAIL".into()
    };

    let _ = bridge.release_stream(sid);

    Ok(AudioInputSmokeResult {
        status,
        backend: "native".into(),
        execution_backend: "native".into(),
        host_audio_backend: host_kind.as_str().into(),
        audio_backend: audio_backend_label(bridge.backend),
        sample_rate: SAMPLE_RATE,
        channels: CHANNELS,
        tone_hz: TONE_HZ,
        samples_generated: tone.len() as u64,
        samples_written: bridge.samples_written,
        bytes_rendered: bridge.bytes_rendered,
        streams_created: 1,
        devices_render: bridge.enumerate_devices(AudioFlow::Render).len(),
        devices_capture: bridge.enumerate_devices(AudioFlow::Capture).len(),
        pipewire_socket_present,
        alsa_nodes,
        input: summarize_input(&input),
        paths,
        gaps,
        wav_path: Some(wav_path.display().to_string()),
        input_obs_path: input.observation_path,
    })
}

fn summarize_input(input: &InputPathResult) -> InputPathSummary {
    InputPathSummary {
        controllers_connected: input.controllers_connected,
        button_events: input.button_events,
        axis_events: input.axis_events,
        vibration_set: input.vibration_set,
        deadzone_applied: input.deadzone_applied,
        evdev_count: input.host.evdev_count,
    }
}

fn audio_backend_label(backend: AudioBackend) -> String {
    match backend {
        AudioBackend::PipeWire => "pipewire".into(),
        AudioBackend::PulseAudio => "pulseaudio".into(),
        AudioBackend::Alsa => "alsa".into(),
        AudioBackend::File => "file".into(),
    }
}

/// Convenience for callers that only need the result struct paths.
pub fn default_side_dir(out_json: &Path) -> PathBuf {
    out_json
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join("gx1-side-effects")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn audio_input_pipeline_smoke() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("strawwu-gx1-{stamp}"));
        let result = run_audio_input_smoke(&dir).unwrap();
        assert!(result.status == "PASS" || result.status == "PARTIAL");
        assert_eq!(result.execution_backend, "native");
        assert!(result.samples_generated > 1000);
        assert!(result.bytes_rendered > 44);
        assert!(result.input.controllers_connected >= 1);
        assert!(result.input.deadzone_applied);
        let wav = dir.join("gx-tone.wav");
        let data = std::fs::read(&wav).unwrap();
        assert!(data.starts_with(b"RIFF"));
        assert!(dir.join("gx-input-obs.json").is_file());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
