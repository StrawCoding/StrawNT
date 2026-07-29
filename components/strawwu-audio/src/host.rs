//! Host audio backend probe — PipeWire preferred, PulseAudio / ALSA as equivalents.
//!
//! Does **not** link libpipewire or claim a full SPA graph; probes sockets / devices
//! so WASAPI bridge evidence can record which host path is available.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum HostAudioKind {
    PipeWire,
    PulseAudio,
    Alsa,
    File,
}

impl HostAudioKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::PipeWire => "pipewire",
            Self::PulseAudio => "pulseaudio",
            Self::Alsa => "alsa",
            Self::File => "file",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostAudioProbe {
    pub selected: HostAudioKind,
    pub pipewire_socket: Option<String>,
    pub pulse_socket: Option<String>,
    pub alsa_pcm_devices: Vec<String>,
    pub notes: Vec<String>,
}

impl HostAudioProbe {
    /// Probe host for PipeWire → Pulse → ALSA → File fallback.
    /// `STRAWWU_AUDIO_BACKEND` may force: pipewire|pulse|pulseaudio|alsa|file.
    pub fn probe() -> Self {
        let forced = std::env::var("STRAWWU_AUDIO_BACKEND")
            .ok()
            .map(|s| s.to_ascii_lowercase());

        let pipewire_socket = find_pipewire_socket();
        let pulse_socket = find_pulse_socket();
        let alsa_pcm_devices = list_alsa_pcm();

        let mut notes = Vec::new();
        if pipewire_socket.is_none() {
            notes.push("pipewire socket not found under XDG_RUNTIME_DIR /run/user".into());
        }
        if pulse_socket.is_none() {
            notes.push("pulseaudio native socket not found".into());
        }
        if alsa_pcm_devices.is_empty() {
            notes.push("no /dev/snd pcm* playback nodes enumerated".into());
        }

        let selected = match forced.as_deref() {
            Some("pipewire") => HostAudioKind::PipeWire,
            Some("pulse") | Some("pulseaudio") => HostAudioKind::PulseAudio,
            Some("alsa") => HostAudioKind::Alsa,
            Some("file") => HostAudioKind::File,
            _ => {
                if pipewire_socket.is_some() {
                    HostAudioKind::PipeWire
                } else if pulse_socket.is_some() {
                    HostAudioKind::PulseAudio
                } else if !alsa_pcm_devices.is_empty() {
                    HostAudioKind::Alsa
                } else {
                    HostAudioKind::File
                }
            }
        };

        notes.push(format!("selected_host_backend={}", selected.as_str()));

        Self {
            selected,
            pipewire_socket: pipewire_socket.map(|p| p.display().to_string()),
            pulse_socket: pulse_socket.map(|p| p.display().to_string()),
            alsa_pcm_devices,
            notes,
        }
    }

    pub fn is_pipewire_or_equivalent(&self) -> bool {
        matches!(
            self.selected,
            HostAudioKind::PipeWire | HostAudioKind::PulseAudio | HostAudioKind::Alsa | HostAudioKind::File
        )
    }
}

fn runtime_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(xdg) = std::env::var("XDG_RUNTIME_DIR") {
        if !xdg.is_empty() {
            dirs.push(PathBuf::from(xdg));
        }
    }
    if let Ok(uid) = std::env::var("SUDO_UID").or_else(|_| std::env::var("UID")) {
        dirs.push(PathBuf::from(format!("/run/user/{uid}")));
    }
    // Common login UIDs when running as root in CI / longtask hosts.
    for uid in [1000u32, 0] {
        dirs.push(PathBuf::from(format!("/run/user/{uid}")));
    }
    dirs.sort();
    dirs.dedup();
    dirs
}

fn find_pipewire_socket() -> Option<PathBuf> {
    for dir in runtime_dirs() {
        for name in ["pipewire-0", "pipewire-0-manager"] {
            let p = dir.join(name);
            if socket_or_exists(&p) {
                return Some(p);
            }
        }
    }
    None
}

fn find_pulse_socket() -> Option<PathBuf> {
    for dir in runtime_dirs() {
        let p = dir.join("pulse").join("native");
        if socket_or_exists(&p) {
            return Some(p);
        }
    }
    None
}

fn socket_or_exists(path: &Path) -> bool {
    path.exists()
}

fn list_alsa_pcm() -> Vec<String> {
    let snd = Path::new("/dev/snd");
    let Ok(rd) = fs::read_dir(snd) else {
        return Vec::new();
    };
    let mut names: Vec<String> = rd
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| n.starts_with("pcm") || n.starts_with("control") || n == "seq" || n == "timer")
        .collect();
    names.sort();
    names
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_selects_some_backend() {
        let probe = HostAudioProbe::probe();
        assert!(probe.is_pipewire_or_equivalent());
        assert!(!probe.notes.is_empty());
    }
}
