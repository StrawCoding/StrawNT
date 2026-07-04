use serde::{Deserialize, Serialize};

pub const BRIDGE_MAGIC: u32 = 0x5357_4232; // "SWB2"
pub const BRIDGE_VERSION: u16 = 1;
pub const MAX_PAYLOAD_SIZE: usize = 65536;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u16)]
pub enum MessageType {
    SyscallRequest = 0x01,
    SyscallResponse = 0x02,
    PolicyQuery = 0x03,
    PolicyDecision = 0x04,
    SessionEvent = 0x10,
    ProcessEvent = 0x11,
}

impl MessageType {
    pub fn from_u16(v: u16) -> Option<Self> {
        match v {
            0x01 => Some(Self::SyscallRequest),
            0x02 => Some(Self::SyscallResponse),
            0x03 => Some(Self::PolicyQuery),
            0x04 => Some(Self::PolicyDecision),
            0x10 => Some(Self::SessionEvent),
            0x11 => Some(Self::ProcessEvent),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum BridgeError {
    Ok = 0,
    PermissionDenied = 1,
    NotImplemented = 2,
    InvalidArgument = 3,
    SessionGone = 4,
    InternalError = 5,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeHeader {
    pub magic: u32,
    pub version: u16,
    pub msg_type: u16,
    pub seq_id: u64,
    pub payload_len: u32,
    pub flags: u32,
    pub reserved: u64,
}

impl BridgeHeader {
    pub const SIZE: usize = 32;

    pub fn new(msg_type: MessageType, seq_id: u64, payload_len: u32) -> Self {
        Self {
            magic: BRIDGE_MAGIC,
            version: BRIDGE_VERSION,
            msg_type: msg_type as u16,
            seq_id,
            payload_len,
            flags: 0,
            reserved: 0,
        }
    }

    pub fn validate(&self) -> Result<(), BridgeError> {
        if self.magic != BRIDGE_MAGIC {
            return Err(BridgeError::InvalidArgument);
        }
        if self.version != BRIDGE_VERSION {
            return Err(BridgeError::InvalidArgument);
        }
        if MessageType::from_u16(self.msg_type).is_none() {
            return Err(BridgeError::InvalidArgument);
        }
        if self.payload_len as usize > MAX_PAYLOAD_SIZE {
            return Err(BridgeError::InvalidArgument);
        }
        Ok(())
    }

    pub fn encode(&self) -> [u8; Self::SIZE] {
        let mut buf = [0u8; Self::SIZE];
        buf[0..4].copy_from_slice(&self.magic.to_le_bytes());
        buf[4..6].copy_from_slice(&self.version.to_le_bytes());
        buf[6..8].copy_from_slice(&self.msg_type.to_le_bytes());
        buf[8..16].copy_from_slice(&self.seq_id.to_le_bytes());
        buf[16..20].copy_from_slice(&self.payload_len.to_le_bytes());
        buf[20..24].copy_from_slice(&self.flags.to_le_bytes());
        buf[24..32].copy_from_slice(&self.reserved.to_le_bytes());
        buf
    }

    pub fn decode(buf: &[u8; Self::SIZE]) -> Self {
        Self {
            magic: u32::from_le_bytes(buf[0..4].try_into().unwrap()),
            version: u16::from_le_bytes(buf[4..6].try_into().unwrap()),
            msg_type: u16::from_le_bytes(buf[6..8].try_into().unwrap()),
            seq_id: u64::from_le_bytes(buf[8..16].try_into().unwrap()),
            payload_len: u32::from_le_bytes(buf[16..20].try_into().unwrap()),
            flags: u32::from_le_bytes(buf[20..24].try_into().unwrap()),
            reserved: u64::from_le_bytes(buf[24..32].try_into().unwrap()),
        }
    }
}

#[derive(Debug, Clone)]
pub struct BridgeMessage {
    pub header: BridgeHeader,
    pub payload: Vec<u8>,
}

impl BridgeMessage {
    pub fn new(msg_type: MessageType, seq_id: u64, payload: Vec<u8>) -> Self {
        let header = BridgeHeader::new(msg_type, seq_id, payload.len() as u32);
        Self { header, payload }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(BridgeHeader::SIZE + self.payload.len());
        buf.extend_from_slice(&self.header.encode());
        buf.extend_from_slice(&self.payload);
        buf
    }

    pub fn decode(data: &[u8]) -> Result<Self, BridgeError> {
        if data.len() < BridgeHeader::SIZE {
            return Err(BridgeError::InvalidArgument);
        }
        let header_bytes: [u8; BridgeHeader::SIZE] =
            data[..BridgeHeader::SIZE].try_into().unwrap();
        let header = BridgeHeader::decode(&header_bytes);
        header.validate()?;

        let payload_end = BridgeHeader::SIZE + header.payload_len as usize;
        if data.len() < payload_end {
            return Err(BridgeError::InvalidArgument);
        }
        let payload = data[BridgeHeader::SIZE..payload_end].to_vec();
        Ok(Self { header, payload })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_roundtrip() {
        let hdr = BridgeHeader::new(MessageType::SyscallRequest, 42, 128);
        let encoded = hdr.encode();
        let decoded = BridgeHeader::decode(&encoded);
        assert_eq!(decoded.magic, BRIDGE_MAGIC);
        assert_eq!(decoded.version, BRIDGE_VERSION);
        assert_eq!(decoded.msg_type, MessageType::SyscallRequest as u16);
        assert_eq!(decoded.seq_id, 42);
        assert_eq!(decoded.payload_len, 128);
    }

    #[test]
    fn message_roundtrip() {
        let payload = b"hello bridge".to_vec();
        let msg = BridgeMessage::new(MessageType::PolicyQuery, 7, payload.clone());
        let encoded = msg.encode();
        let decoded = BridgeMessage::decode(&encoded).unwrap();
        assert_eq!(decoded.header.seq_id, 7);
        assert_eq!(decoded.payload, payload);
    }

    #[test]
    fn invalid_magic_rejected() {
        let mut hdr = BridgeHeader::new(MessageType::SyscallRequest, 1, 0);
        hdr.magic = 0xDEAD_BEEF;
        assert!(hdr.validate().is_err());
    }

    #[test]
    fn oversized_payload_rejected() {
        let hdr = BridgeHeader::new(MessageType::SyscallRequest, 1, MAX_PAYLOAD_SIZE as u32 + 1);
        assert!(hdr.validate().is_err());
    }
}
