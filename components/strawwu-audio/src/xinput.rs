use serde::{Deserialize, Serialize};

pub const XINPUT_MAX_CONTROLLERS: usize = 4;
pub const XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE: i16 = 7849;
pub const XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE: i16 = 8689;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum XInputButton {
    DpadUp,
    DpadDown,
    DpadLeft,
    DpadRight,
    Start,
    Back,
    LeftThumb,
    RightThumb,
    LeftShoulder,
    RightShoulder,
    A,
    B,
    X,
    Y,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct XInputState {
    pub connected: bool,
    pub buttons: u16,
    pub left_trigger: u8,
    pub right_trigger: u8,
    pub left_thumb_x: i16,
    pub left_thumb_y: i16,
    pub right_thumb_x: i16,
    pub right_thumb_y: i16,
}

impl XInputState {
    pub fn is_button_pressed(&self, button: XInputButton) -> bool {
        let mask = match button {
            XInputButton::DpadUp => 0x0001,
            XInputButton::DpadDown => 0x0002,
            XInputButton::DpadLeft => 0x0004,
            XInputButton::DpadRight => 0x0008,
            XInputButton::Start => 0x0010,
            XInputButton::Back => 0x0020,
            XInputButton::LeftThumb => 0x0040,
            XInputButton::RightThumb => 0x0080,
            XInputButton::LeftShoulder => 0x0100,
            XInputButton::RightShoulder => 0x0200,
            XInputButton::A => 0x1000,
            XInputButton::B => 0x2000,
            XInputButton::X => 0x4000,
            XInputButton::Y => 0x8000,
        };
        (self.buttons & mask) != 0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct XInputVibration {
    pub left_motor: u16,
    pub right_motor: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ControllerType {
    Gamepad,
    Wheel,
    ArcadeStick,
    FlightStick,
    DancePad,
    Guitar,
    DrumKit,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XInputCapabilities {
    pub controller_type: ControllerType,
    pub has_vibration: bool,
    pub has_voice: bool,
    pub button_count: u8,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct XInputSubsystem {
    pub controllers: [XInputState; XINPUT_MAX_CONTROLLERS],
    vibrations: [XInputVibration; XINPUT_MAX_CONTROLLERS],
    capabilities: [XInputCapabilities; XINPUT_MAX_CONTROLLERS],
}

impl XInputSubsystem {
    pub fn new() -> Self {
        let default_caps = XInputCapabilities {
            controller_type: ControllerType::Gamepad,
            has_vibration: true,
            has_voice: false,
            button_count: 14,
        };
        Self {
            controllers: [
                XInputState::default(),
                XInputState::default(),
                XInputState::default(),
                XInputState::default(),
            ],
            vibrations: [XInputVibration { left_motor: 0, right_motor: 0 }; XINPUT_MAX_CONTROLLERS],
            capabilities: [default_caps.clone(), default_caps.clone(), default_caps.clone(), default_caps],
        }
    }

    pub fn get_state(&self, index: u32) -> Result<&XInputState, XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        let state = &self.controllers[index as usize];
        if !state.connected {
            return Err(XInputError::NotConnected);
        }
        Ok(state)
    }

    pub fn connect_controller(&mut self, index: u32) -> Result<(), XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        self.controllers[index as usize].connected = true;
        Ok(())
    }

    pub fn disconnect_controller(&mut self, index: u32) -> Result<(), XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        self.controllers[index as usize].connected = false;
        self.vibrations[index as usize] = XInputVibration { left_motor: 0, right_motor: 0 };
        Ok(())
    }

    pub fn set_state(&mut self, index: u32, state: XInputState) -> Result<(), XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        self.controllers[index as usize] = state;
        Ok(())
    }

    pub fn connected_count(&self) -> usize {
        self.controllers.iter().filter(|c| c.connected).count()
    }

    pub fn set_vibration(&mut self, index: u32, left_motor: u16, right_motor: u16) -> Result<(), XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        if !self.controllers[index as usize].connected {
            return Err(XInputError::NotConnected);
        }
        self.vibrations[index as usize] = XInputVibration { left_motor, right_motor };
        Ok(())
    }

    pub fn get_vibration(&self, index: u32) -> Result<&XInputVibration, XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        Ok(&self.vibrations[index as usize])
    }

    pub fn get_capabilities(&self, index: u32) -> Result<&XInputCapabilities, XInputError> {
        if index as usize >= XINPUT_MAX_CONTROLLERS {
            return Err(XInputError::InvalidIndex);
        }
        if !self.controllers[index as usize].connected {
            return Err(XInputError::NotConnected);
        }
        Ok(&self.capabilities[index as usize])
    }
}

pub fn apply_deadzone(value: i16, deadzone: i16) -> i16 {
    let dz = deadzone.unsigned_abs();
    if (value as i32).unsigned_abs() < dz as u32 {
        0
    } else {
        value
    }
}

impl Default for XInputSubsystem {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum XInputError {
    #[error("controller index out of range")]
    InvalidIndex,
    #[error("controller not connected")]
    NotConnected,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xinput_default_disconnected() {
        let xi = XInputSubsystem::new();
        assert_eq!(xi.connected_count(), 0);
        assert!(xi.get_state(0).is_err());
    }

    #[test]
    fn xinput_connect_controller() {
        let mut xi = XInputSubsystem::new();
        xi.connect_controller(0).unwrap();
        assert_eq!(xi.connected_count(), 1);
        let state = xi.get_state(0).unwrap();
        assert!(state.connected);
    }

    #[test]
    fn xinput_button_press() {
        let mut state = XInputState::default();
        state.connected = true;
        state.buttons = 0x1000; // A button
        assert!(state.is_button_pressed(XInputButton::A));
        assert!(!state.is_button_pressed(XInputButton::B));
    }

    #[test]
    fn xinput_invalid_index() {
        let xi = XInputSubsystem::new();
        assert!(xi.get_state(4).is_err());
    }

    #[test]
    fn xinput_set_state() {
        let mut xi = XInputSubsystem::new();
        let state = XInputState {
            connected: true,
            buttons: 0x0010,
            left_trigger: 128,
            right_trigger: 0,
            left_thumb_x: 1000,
            left_thumb_y: -500,
            right_thumb_x: 0,
            right_thumb_y: 0,
        };
        xi.set_state(1, state).unwrap();
        let got = xi.get_state(1).unwrap();
        assert!(got.is_button_pressed(XInputButton::Start));
        assert_eq!(got.left_trigger, 128);
    }

    #[test]
    fn xinput_disconnect_controller() {
        let mut xi = XInputSubsystem::new();
        xi.connect_controller(0).unwrap();
        assert_eq!(xi.connected_count(), 1);
        xi.disconnect_controller(0).unwrap();
        assert_eq!(xi.connected_count(), 0);
        assert!(xi.get_state(0).is_err());
    }

    #[test]
    fn xinput_disconnect_clears_vibration() {
        let mut xi = XInputSubsystem::new();
        xi.connect_controller(0).unwrap();
        xi.set_vibration(0, 32000, 16000).unwrap();
        xi.disconnect_controller(0).unwrap();
        let vib = xi.get_vibration(0).unwrap();
        assert_eq!(vib.left_motor, 0);
        assert_eq!(vib.right_motor, 0);
    }

    #[test]
    fn xinput_vibration() {
        let mut xi = XInputSubsystem::new();
        xi.connect_controller(2).unwrap();
        xi.set_vibration(2, 65535, 32768).unwrap();
        let vib = xi.get_vibration(2).unwrap();
        assert_eq!(vib.left_motor, 65535);
        assert_eq!(vib.right_motor, 32768);
    }

    #[test]
    fn xinput_vibration_not_connected() {
        let mut xi = XInputSubsystem::new();
        assert!(xi.set_vibration(0, 100, 100).is_err());
    }

    #[test]
    fn xinput_capabilities() {
        let mut xi = XInputSubsystem::new();
        xi.connect_controller(0).unwrap();
        let caps = xi.get_capabilities(0).unwrap();
        assert_eq!(caps.controller_type, ControllerType::Gamepad);
        assert!(caps.has_vibration);
        assert_eq!(caps.button_count, 14);
    }

    #[test]
    fn xinput_deadzone_filters_small_values() {
        assert_eq!(apply_deadzone(100, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE), 0);
        assert_eq!(apply_deadzone(-100, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE), 0);
        assert_eq!(apply_deadzone(20000, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE), 20000);
        assert_eq!(apply_deadzone(-20000, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE), -20000);
        assert_eq!(apply_deadzone(0, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE), 0);
    }
}
