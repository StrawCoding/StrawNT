//! Basic input path — XInput controller mapping + host evdev node probe.
//!
//! Observable evidence is written as JSON (button/axis/vibration events).
//! Does not claim full DirectInput / HID stack completeness.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

use crate::xinput::{
    apply_deadzone, XInputButton, XInputState, XInputSubsystem, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
    XINPUT_MAX_CONTROLLERS,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputEventObs {
    pub kind: String,
    pub detail: String,
    pub index: Option<u32>,
    pub buttons: Option<u16>,
    pub left_thumb_x: Option<i16>,
    pub left_thumb_filtered: Option<i16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostInputProbe {
    pub evdev_nodes: Vec<String>,
    pub evdev_count: usize,
    pub notes: Vec<String>,
}

impl HostInputProbe {
    pub fn probe() -> Self {
        let mut nodes = Vec::new();
        let mut notes = Vec::new();
        let input_dir = Path::new("/dev/input");
        if let Ok(rd) = fs::read_dir(input_dir) {
            for ent in rd.flatten() {
                let name = ent.file_name().to_string_lossy().into_owned();
                if name.starts_with("event") || name.starts_with("js") || name == "mice" {
                    nodes.push(name);
                }
            }
        } else {
            notes.push("/dev/input not readable".into());
        }
        nodes.sort();
        if nodes.is_empty() {
            notes.push("no evdev/js nodes enumerated".into());
        }
        let evdev_count = nodes.iter().filter(|n| n.starts_with("event")).count();
        Self {
            evdev_nodes: nodes,
            evdev_count,
            notes,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputPathResult {
    pub controllers_connected: usize,
    pub button_events: u32,
    pub axis_events: u32,
    pub vibration_set: bool,
    pub deadzone_applied: bool,
    pub host: HostInputProbe,
    pub events: Vec<InputEventObs>,
    pub observation_path: Option<String>,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum InputPathError {
    #[error("xinput: {0}")]
    XInput(String),
    #[error("io: {0}")]
    Io(String),
}

/// Run a deterministic XInput + host-probe input smoke; optionally write observation JSON.
pub fn run_input_path_smoke(obs_path: Option<&Path>) -> Result<InputPathResult, InputPathError> {
    let host = HostInputProbe::probe();
    let mut xi = XInputSubsystem::new();
    let mut events = Vec::new();

    xi.connect_controller(0)
        .map_err(|e| InputPathError::XInput(e.to_string()))?;
    events.push(InputEventObs {
        kind: "connect".into(),
        detail: "controller 0 connected".into(),
        index: Some(0),
        buttons: None,
        left_thumb_x: None,
        left_thumb_filtered: None,
    });

    // Synthetic A + Start press with left stick near deadzone then past it.
    let raw_thumb = 2000i16; // inside left deadzone
    let filtered = apply_deadzone(raw_thumb, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    let state = XInputState {
        connected: true,
        buttons: 0x1000 | 0x0010, // A | Start
        left_trigger: 64,
        right_trigger: 0,
        left_thumb_x: raw_thumb,
        left_thumb_y: 0,
        right_thumb_x: 0,
        right_thumb_y: 0,
    };
    xi.set_state(0, state)
        .map_err(|e| InputPathError::XInput(e.to_string()))?;
    let got = xi
        .get_state(0)
        .map_err(|e| InputPathError::XInput(e.to_string()))?;
    assert_button(got, XInputButton::A)?;
    assert_button(got, XInputButton::Start)?;
    events.push(InputEventObs {
        kind: "button".into(),
        detail: "A+Start pressed".into(),
        index: Some(0),
        buttons: Some(got.buttons),
        left_thumb_x: Some(raw_thumb),
        left_thumb_filtered: Some(filtered),
    });

    let past_dz = 20000i16;
    let filtered_past = apply_deadzone(past_dz, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
    let mut axis_state = got.clone();
    axis_state.left_thumb_x = past_dz;
    xi.set_state(0, axis_state)
        .map_err(|e| InputPathError::XInput(e.to_string()))?;
    events.push(InputEventObs {
        kind: "axis".into(),
        detail: format!("left_thumb_x={past_dz} filtered={filtered_past}"),
        index: Some(0),
        buttons: None,
        left_thumb_x: Some(past_dz),
        left_thumb_filtered: Some(filtered_past),
    });

    xi.set_vibration(0, 12000, 8000)
        .map_err(|e| InputPathError::XInput(e.to_string()))?;
    let vib = xi
        .get_vibration(0)
        .map_err(|e| InputPathError::XInput(e.to_string()))?
        .clone();
    events.push(InputEventObs {
        kind: "vibration".into(),
        detail: format!("left={} right={}", vib.left_motor, vib.right_motor),
        index: Some(0),
        buttons: None,
        left_thumb_x: None,
        left_thumb_filtered: None,
    });

    // Mark remaining slots as explicitly disconnected for matrix clarity.
    for i in 1..XINPUT_MAX_CONTROLLERS as u32 {
        let _ = xi.disconnect_controller(i);
    }

    let observation_path = if let Some(path) = obs_path {
        write_obs(path, &events, &host, &xi)?;
        Some(path.display().to_string())
    } else {
        None
    };

    Ok(InputPathResult {
        controllers_connected: xi.connected_count(),
        button_events: 1,
        axis_events: 1,
        vibration_set: vib.left_motor > 0,
        deadzone_applied: filtered == 0 && filtered_past == past_dz,
        host,
        events,
        observation_path,
    })
}

fn assert_button(state: &XInputState, button: XInputButton) -> Result<(), InputPathError> {
    if state.is_button_pressed(button) {
        Ok(())
    } else {
        Err(InputPathError::XInput(format!(
            "expected button {:?} pressed",
            button
        )))
    }
}

fn write_obs(
    path: &Path,
    events: &[InputEventObs],
    host: &HostInputProbe,
    xi: &XInputSubsystem,
) -> Result<(), InputPathError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| InputPathError::Io(e.to_string()))?;
    }
    let doc = serde_json::json!({
        "schema": "strawwu-portable-gx-input-obs/v1",
        "host": host,
        "controllers_connected": xi.connected_count(),
        "max_controllers": XINPUT_MAX_CONTROLLERS,
        "events": events,
        "execution_backend": "native",
    });
    let body = serde_json::to_string_pretty(&doc).map_err(|e| InputPathError::Io(e.to_string()))?;
    fs::write(path, body + "\n").map_err(|e| InputPathError::Io(e.to_string()))?;
    let _ = PathBuf::from(path.display().to_string());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn input_path_smoke_writes_obs() {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("strawwu-gx1-input-{stamp}"));
        fs::create_dir_all(&dir).unwrap();
        let obs = dir.join("gx-input-obs.json");
        let result = run_input_path_smoke(Some(&obs)).unwrap();
        assert_eq!(result.controllers_connected, 1);
        assert!(result.deadzone_applied);
        assert!(result.vibration_set);
        assert!(obs.is_file());
        let text = fs::read_to_string(&obs).unwrap();
        assert!(text.contains("button"));
        let _ = fs::remove_dir_all(&dir);
    }
}
