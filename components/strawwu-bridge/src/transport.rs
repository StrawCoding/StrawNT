use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::abi::{BridgeError, BridgeHeader, BridgeMessage, MessageType};

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteResult {
    pub handler_name: String,
    pub latency_us: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TransportStats {
    pub messages_sent: u64,
    pub messages_received: u64,
    pub bytes_transferred: u64,
}

#[derive(Debug)]
pub struct MessageRouter {
    handlers: HashMap<u16, String>,
    pending: Vec<BridgeMessage>,
    pub stats: TransportStats,
}

impl MessageRouter {
    pub fn new() -> Self {
        Self {
            handlers: HashMap::new(),
            pending: Vec::new(),
            stats: TransportStats::default(),
        }
    }

    pub fn register_handler(&mut self, msg_type: MessageType, handler_name: &str) {
        self.handlers.insert(msg_type as u16, handler_name.to_string());
    }

    pub fn route(&self, msg: &BridgeMessage) -> Result<RouteResult, BridgeError> {
        let msg_type_id = msg.header.msg_type;
        match self.handlers.get(&msg_type_id) {
            Some(handler_name) => {
                let payload_len = msg.payload.len() as u64;
                let latency_us = 10 + payload_len / 64;
                Ok(RouteResult {
                    handler_name: handler_name.clone(),
                    latency_us,
                })
            }
            None => Err(BridgeError::NotImplemented),
        }
    }

    pub fn enqueue(&mut self, msg: BridgeMessage) {
        let msg_bytes = msg.payload.len() as u64 + BridgeHeader::SIZE as u64;
        self.pending.push(msg);
        self.stats.messages_received += 1;
        self.stats.bytes_transferred += msg_bytes;
    }

    pub fn drain_pending(&mut self) -> Vec<BridgeMessage> {
        let drained = std::mem::take(&mut self.pending);
        self.stats.messages_sent += drained.len() as u64;
        drained
    }

    pub fn pending_count(&self) -> usize {
        self.pending.len()
    }
}

impl Default for MessageRouter {
    fn default() -> Self {
        Self::new()
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

    #[test]
    fn router_register_and_route() {
        let mut router = MessageRouter::new();
        router.register_handler(MessageType::SyscallRequest, "syscall_handler");
        router.register_handler(MessageType::PolicyQuery, "policy_handler");

        let msg = BridgeMessage::new(MessageType::SyscallRequest, 1, vec![0u8; 32]);
        let result = router.route(&msg).unwrap();
        assert_eq!(result.handler_name, "syscall_handler");
        assert!(result.latency_us >= 10);
    }

    #[test]
    fn router_unregistered_type_returns_error() {
        let router = MessageRouter::new();
        let msg = BridgeMessage::new(MessageType::SessionEvent, 1, vec![]);
        let result = router.route(&msg);
        assert!(result.is_err());
    }

    #[test]
    fn router_pending_count_and_drain() {
        let mut router = MessageRouter::new();
        assert_eq!(router.pending_count(), 0);

        router.enqueue(BridgeMessage::new(MessageType::SyscallRequest, 1, vec![1, 2, 3]));
        router.enqueue(BridgeMessage::new(MessageType::PolicyQuery, 2, vec![4, 5]));
        assert_eq!(router.pending_count(), 2);

        let drained = router.drain_pending();
        assert_eq!(drained.len(), 2);
        assert_eq!(router.pending_count(), 0);
    }

    #[test]
    fn transport_stats_tracking() {
        let mut router = MessageRouter::new();
        router.enqueue(BridgeMessage::new(MessageType::SyscallRequest, 1, vec![0u8; 100]));
        router.enqueue(BridgeMessage::new(MessageType::SyscallResponse, 2, vec![0u8; 200]));

        assert_eq!(router.stats.messages_received, 2);
        assert!(router.stats.bytes_transferred > 0);

        router.drain_pending();
        assert_eq!(router.stats.messages_sent, 2);
    }

    #[test]
    fn router_route_latency_scales_with_payload() {
        let router = {
            let mut r = MessageRouter::new();
            r.register_handler(MessageType::SyscallRequest, "handler");
            r
        };

        let small = BridgeMessage::new(MessageType::SyscallRequest, 1, vec![]);
        let large = BridgeMessage::new(MessageType::SyscallRequest, 2, vec![0u8; 1024]);

        let small_result = router.route(&small).unwrap();
        let large_result = router.route(&large).unwrap();
        assert!(large_result.latency_us > small_result.latency_us);
    }

    #[test]
    fn router_overwrite_handler() {
        let mut router = MessageRouter::new();
        router.register_handler(MessageType::SyscallRequest, "old_handler");
        router.register_handler(MessageType::SyscallRequest, "new_handler");

        let msg = BridgeMessage::new(MessageType::SyscallRequest, 1, vec![]);
        let result = router.route(&msg).unwrap();
        assert_eq!(result.handler_name, "new_handler");
    }
}
