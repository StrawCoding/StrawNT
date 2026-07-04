use serde::{Deserialize, Serialize};

pub const XINPUT_MAX_CONTROLLERS: usize = 4;

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

#[derive(Debug, Serialize, Deserialize)]
pub struct XInputSubsystem {
    pub controllers: [XInputState; XINPUT_MAX_CONTROLLERS],
}

impl XInputSubsystem {
    pub fn new() -> Self {
        Self {
            controllers: [
                XInputState::default(),
                XInputState::default(),
                XInputState::default(),
                XInputState::default(),
            ],
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
}
