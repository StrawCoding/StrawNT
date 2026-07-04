use std::path::{Path, PathBuf};

use crate::abi::{BridgeError, BridgeMessage};

pub const BRIDGE_SOCKET_DIR: &str = "/run/strawwu";

pub fn socket_path(session_id: &str) -> PathBuf {
    PathBuf::from(BRIDGE_SOCKET_DIR).join(format!("bridge-{session_id}.sock"))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportKind {
    UnixSeqpacket,
    Vsock,
}

pub struct BridgeSocket {
    pub session_id: String,
    pub kind: TransportKind,
    path: PathBuf,
}

impl BridgeSocket {
    pub fn new(session_id: impl Into<String>, kind: TransportKind) -> Self {
        let session_id = session_id.into();
        let path = socket_path(&session_id);
        Self {
            session_id,
            kind,
            path,
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn validate_message(data: &[u8]) -> Result<BridgeMessage, BridgeError> {
        BridgeMessage::decode(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_path_format() {
        let p = socket_path("abc123");
        assert_eq!(p.to_str().unwrap(), "/run/strawwu/bridge-abc123.sock");
    }

    #[test]
    fn bridge_socket_creation() {
        let sock = BridgeSocket::new("test-session", TransportKind::UnixSeqpacket);
        assert_eq!(sock.session_id, "test-session");
        assert_eq!(sock.kind, TransportKind::UnixSeqpacket);
        assert!(sock.path().to_str().unwrap().contains("test-session"));
    }
}
