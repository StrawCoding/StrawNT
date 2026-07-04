use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PipeDirection {
    In,
    Out,
    Duplex,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamedPipe {
    pub name: String,
    pub direction: PipeDirection,
    pub creator_pid: u64,
    pub connected_pid: Option<u64>,
    pub buffer: Vec<u8>,
    pub max_buffer_size: usize,
}

impl NamedPipe {
    pub fn create(name: &str, direction: PipeDirection, creator_pid: u64) -> Self {
        Self {
            name: name.to_string(),
            direction,
            creator_pid,
            connected_pid: None,
            buffer: Vec::new(),
            max_buffer_size: 65536,
        }
    }

    pub fn connect(&mut self, pid: u64) -> Result<(), PipeError> {
        if self.connected_pid.is_some() {
            return Err(PipeError::AlreadyConnected);
        }
        self.connected_pid = Some(pid);
        Ok(())
    }

    pub fn disconnect(&mut self) {
        self.connected_pid = None;
    }

    pub fn write(&mut self, data: &[u8]) -> Result<usize, PipeError> {
        if self.direction == PipeDirection::In {
            return Err(PipeError::WrongDirection);
        }
        let available = self.max_buffer_size - self.buffer.len();
        let to_write = data.len().min(available);
        self.buffer.extend_from_slice(&data[..to_write]);
        Ok(to_write)
    }

    pub fn read(&mut self, max_len: usize) -> Vec<u8> {
        if self.direction == PipeDirection::Out {
            return Vec::new();
        }
        let n = max_len.min(self.buffer.len());
        self.buffer.drain(..n).collect()
    }

    pub fn is_connected(&self) -> bool {
        self.connected_pid.is_some()
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum PipeError {
    #[error("pipe already connected")]
    AlreadyConnected,
    #[error("wrong pipe direction for this operation")]
    WrongDirection,
    #[error("pipe not found")]
    NotFound,
    #[error("pipe buffer full")]
    BufferFull,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct PipeNamespace {
    pipes: Vec<NamedPipe>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedMemorySection {
    pub name: String,
    pub size: usize,
    pub data: Vec<u8>,
    pub creator_pid: u64,
    pub mapped_pids: Vec<u64>,
}

impl SharedMemorySection {
    pub fn create(name: &str, size: usize, creator_pid: u64) -> Self {
        Self {
            name: name.to_string(),
            size,
            data: vec![0u8; size],
            creator_pid,
            mapped_pids: vec![creator_pid],
        }
    }

    pub fn map_view(&mut self, pid: u64) -> Result<(), SectionError> {
        if self.mapped_pids.contains(&pid) {
            return Err(SectionError::AlreadyMapped);
        }
        self.mapped_pids.push(pid);
        Ok(())
    }

    pub fn unmap_view(&mut self, pid: u64) -> Result<(), SectionError> {
        let before = self.mapped_pids.len();
        self.mapped_pids.retain(|&p| p != pid);
        if self.mapped_pids.len() == before {
            return Err(SectionError::NotMapped);
        }
        Ok(())
    }

    pub fn write(&mut self, offset: usize, data: &[u8]) -> Result<usize, SectionError> {
        if offset >= self.size {
            return Err(SectionError::OutOfBounds);
        }
        let available = self.size - offset;
        let to_write = data.len().min(available);
        self.data[offset..offset + to_write].copy_from_slice(&data[..to_write]);
        Ok(to_write)
    }

    pub fn read(&self, offset: usize, len: usize) -> Result<Vec<u8>, SectionError> {
        if offset >= self.size {
            return Err(SectionError::OutOfBounds);
        }
        let available = self.size - offset;
        let to_read = len.min(available);
        Ok(self.data[offset..offset + to_read].to_vec())
    }

    pub fn is_mapped_by(&self, pid: u64) -> bool {
        self.mapped_pids.contains(&pid)
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum SectionError {
    #[error("section not found")]
    NotFound,
    #[error("process already has a view mapped")]
    AlreadyMapped,
    #[error("process does not have a view mapped")]
    NotMapped,
    #[error("offset out of bounds")]
    OutOfBounds,
    #[error("section name already exists")]
    NameConflict,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct SharedMemoryNamespace {
    sections: Vec<SharedMemorySection>,
}

impl SharedMemoryNamespace {
    pub fn new() -> Self {
        Self { sections: Vec::new() }
    }

    pub fn create_section(&mut self, name: &str, size: usize, creator_pid: u64) -> Result<usize, SectionError> {
        if self.sections.iter().any(|s| s.name == name) {
            return Err(SectionError::NameConflict);
        }
        let idx = self.sections.len();
        self.sections.push(SharedMemorySection::create(name, size, creator_pid));
        Ok(idx)
    }

    pub fn map_view(&mut self, name: &str, pid: u64) -> Result<(), SectionError> {
        let section = self.sections.iter_mut()
            .find(|s| s.name == name)
            .ok_or(SectionError::NotFound)?;
        section.map_view(pid)
    }

    pub fn unmap_view(&mut self, name: &str, pid: u64) -> Result<(), SectionError> {
        let section = self.sections.iter_mut()
            .find(|s| s.name == name)
            .ok_or(SectionError::NotFound)?;
        section.unmap_view(pid)
    }

    pub fn write_section(&mut self, name: &str, offset: usize, data: &[u8]) -> Result<usize, SectionError> {
        let section = self.sections.iter_mut()
            .find(|s| s.name == name)
            .ok_or(SectionError::NotFound)?;
        section.write(offset, data)
    }

    pub fn read_section(&self, name: &str, offset: usize, len: usize) -> Result<Vec<u8>, SectionError> {
        let section = self.sections.iter()
            .find(|s| s.name == name)
            .ok_or(SectionError::NotFound)?;
        section.read(offset, len)
    }

    pub fn section_count(&self) -> usize {
        self.sections.len()
    }

    pub fn get_section(&self, name: &str) -> Option<&SharedMemorySection> {
        self.sections.iter().find(|s| s.name == name)
    }
}

// --- Event Objects ---

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventObject {
    pub name: String,
    pub signaled: bool,
    pub auto_reset: bool,
    pub waiting_pids: Vec<u64>,
}

impl EventObject {
    pub fn new(name: &str, auto_reset: bool) -> Self {
        Self {
            name: name.to_string(),
            signaled: false,
            auto_reset,
            waiting_pids: Vec::new(),
        }
    }

    pub fn signal(&mut self) -> Vec<u64> {
        self.signaled = true;
        let woken = self.waiting_pids.clone();
        self.waiting_pids.clear();
        if self.auto_reset && !woken.is_empty() {
            self.signaled = false;
        }
        woken
    }

    pub fn reset(&mut self) {
        self.signaled = false;
    }

    pub fn wait(&mut self, pid: u64) -> bool {
        if self.signaled {
            if self.auto_reset {
                self.signaled = false;
            }
            return true;
        }
        if !self.waiting_pids.contains(&pid) {
            self.waiting_pids.push(pid);
        }
        false
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum EventError {
    #[error("event not found")]
    NotFound,
    #[error("event name already exists")]
    NameConflict,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct EventNamespace {
    events: Vec<EventObject>,
}

impl EventNamespace {
    pub fn new() -> Self {
        Self { events: Vec::new() }
    }

    pub fn create_event(&mut self, name: &str, auto_reset: bool) -> Result<usize, EventError> {
        if self.events.iter().any(|e| e.name == name) {
            return Err(EventError::NameConflict);
        }
        let idx = self.events.len();
        self.events.push(EventObject::new(name, auto_reset));
        Ok(idx)
    }

    pub fn open_event(&self, name: &str) -> Result<usize, EventError> {
        self.events.iter().position(|e| e.name == name)
            .ok_or(EventError::NotFound)
    }

    pub fn signal_event(&mut self, name: &str) -> Result<Vec<u64>, EventError> {
        let event = self.events.iter_mut()
            .find(|e| e.name == name)
            .ok_or(EventError::NotFound)?;
        Ok(event.signal())
    }

    pub fn reset_event(&mut self, name: &str) -> Result<(), EventError> {
        let event = self.events.iter_mut()
            .find(|e| e.name == name)
            .ok_or(EventError::NotFound)?;
        event.reset();
        Ok(())
    }

    pub fn wait_event(&mut self, name: &str, pid: u64) -> Result<bool, EventError> {
        let event = self.events.iter_mut()
            .find(|e| e.name == name)
            .ok_or(EventError::NotFound)?;
        Ok(event.wait(pid))
    }

    pub fn close_event(&mut self, name: &str) -> Result<(), EventError> {
        let idx = self.events.iter().position(|e| e.name == name)
            .ok_or(EventError::NotFound)?;
        self.events.remove(idx);
        Ok(())
    }

    pub fn event_count(&self) -> usize {
        self.events.len()
    }
}

// --- ALPC (Advanced Local Procedure Call) ---

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpcMessage {
    pub sender_pid: u64,
    pub message_id: u64,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum AlpcError {
    #[error("port not found")]
    NotFound,
    #[error("port name already exists")]
    NameConflict,
    #[error("client not connected to port")]
    NotConnected,
    #[error("no messages available")]
    NoMessages,
    #[error("client already connected")]
    AlreadyConnected,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlpcPort {
    pub name: String,
    pub server_pid: u64,
    pub connected_clients: Vec<u64>,
    pub message_queue: VecDeque<AlpcMessage>,
    next_message_id: u64,
}

impl AlpcPort {
    pub fn new(name: &str, server_pid: u64) -> Self {
        Self {
            name: name.to_string(),
            server_pid,
            connected_clients: Vec::new(),
            message_queue: VecDeque::new(),
            next_message_id: 1,
        }
    }

    pub fn connect(&mut self, client_pid: u64) -> Result<(), AlpcError> {
        if self.connected_clients.contains(&client_pid) {
            return Err(AlpcError::AlreadyConnected);
        }
        self.connected_clients.push(client_pid);
        Ok(())
    }

    pub fn disconnect(&mut self, client_pid: u64) -> Result<(), AlpcError> {
        let before = self.connected_clients.len();
        self.connected_clients.retain(|&p| p != client_pid);
        if self.connected_clients.len() == before {
            Err(AlpcError::NotConnected)
        } else {
            Ok(())
        }
    }

    pub fn send(&mut self, sender_pid: u64, data: &[u8]) -> Result<u64, AlpcError> {
        if sender_pid != self.server_pid && !self.connected_clients.contains(&sender_pid) {
            return Err(AlpcError::NotConnected);
        }
        let msg_id = self.next_message_id;
        self.next_message_id += 1;
        self.message_queue.push_back(AlpcMessage {
            sender_pid,
            message_id: msg_id,
            data: data.to_vec(),
        });
        Ok(msg_id)
    }

    pub fn receive(&mut self) -> Result<AlpcMessage, AlpcError> {
        self.message_queue.pop_front().ok_or(AlpcError::NoMessages)
    }

    pub fn pending_message_count(&self) -> usize {
        self.message_queue.len()
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct AlpcNamespace {
    ports: Vec<AlpcPort>,
}

impl AlpcNamespace {
    pub fn new() -> Self {
        Self { ports: Vec::new() }
    }

    pub fn create_port(&mut self, name: &str, server_pid: u64) -> Result<usize, AlpcError> {
        if self.ports.iter().any(|p| p.name == name) {
            return Err(AlpcError::NameConflict);
        }
        let idx = self.ports.len();
        self.ports.push(AlpcPort::new(name, server_pid));
        Ok(idx)
    }

    pub fn connect_port(&mut self, name: &str, client_pid: u64) -> Result<(), AlpcError> {
        let port = self.ports.iter_mut()
            .find(|p| p.name == name)
            .ok_or(AlpcError::NotFound)?;
        port.connect(client_pid)
    }

    pub fn send_message(&mut self, port_name: &str, sender_pid: u64, data: &[u8]) -> Result<u64, AlpcError> {
        let port = self.ports.iter_mut()
            .find(|p| p.name == port_name)
            .ok_or(AlpcError::NotFound)?;
        port.send(sender_pid, data)
    }

    pub fn receive_message(&mut self, port_name: &str) -> Result<AlpcMessage, AlpcError> {
        let port = self.ports.iter_mut()
            .find(|p| p.name == port_name)
            .ok_or(AlpcError::NotFound)?;
        port.receive()
    }

    pub fn port_count(&self) -> usize {
        self.ports.len()
    }
}

// --- Session IPC Manager ---

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct SessionIpcManager {
    pub pipes: PipeNamespace,
    pub shared_memory: SharedMemoryNamespace,
    pub events: EventNamespace,
    pub alpc: AlpcNamespace,
}

impl SessionIpcManager {
    pub fn new() -> Self {
        Self {
            pipes: PipeNamespace::new(),
            shared_memory: SharedMemoryNamespace::new(),
            events: EventNamespace::new(),
            alpc: AlpcNamespace::new(),
        }
    }

    pub fn total_object_count(&self) -> usize {
        self.pipes.pipe_count()
            + self.shared_memory.section_count()
            + self.events.event_count()
            + self.alpc.port_count()
    }
}

impl PipeNamespace {
    pub fn new() -> Self {
        Self { pipes: Vec::new() }
    }

    pub fn create_pipe(&mut self, name: &str, direction: PipeDirection, creator_pid: u64) -> Result<usize, PipeError> {
        let pipe = NamedPipe::create(name, direction, creator_pid);
        let idx = self.pipes.len();
        self.pipes.push(pipe);
        Ok(idx)
    }

    pub fn connect_pipe(&mut self, name: &str, pid: u64) -> Result<usize, PipeError> {
        for (i, pipe) in self.pipes.iter_mut().enumerate() {
            if pipe.name == name {
                pipe.connect(pid)?;
                return Ok(i);
            }
        }
        Err(PipeError::NotFound)
    }

    pub fn write_pipe(&mut self, name: &str, data: &[u8]) -> Result<usize, PipeError> {
        for pipe in &mut self.pipes {
            if pipe.name == name {
                return pipe.write(data);
            }
        }
        Err(PipeError::NotFound)
    }

    pub fn read_pipe(&mut self, name: &str, max_len: usize) -> Result<Vec<u8>, PipeError> {
        for pipe in &mut self.pipes {
            if pipe.name == name {
                return Ok(pipe.read(max_len));
            }
        }
        Err(PipeError::NotFound)
    }

    pub fn pipe_count(&self) -> usize {
        self.pipes.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pipe_create_and_write() {
        let mut pipe = NamedPipe::create("\\\\.\\pipe\\test", PipeDirection::Duplex, 100);
        assert!(!pipe.is_connected());

        pipe.connect(200).unwrap();
        assert!(pipe.is_connected());

        let written = pipe.write(b"hello pipe").unwrap();
        assert_eq!(written, 10);

        let data = pipe.read(1024);
        assert_eq!(data, b"hello pipe");
    }

    #[test]
    fn pipe_namespace_interprocess() {
        let mut ns = PipeNamespace::new();
        let pipe_name = "\\\\.\\pipe\\writer_reader";

        ns.create_pipe(pipe_name, PipeDirection::Duplex, 100).unwrap();
        ns.connect_pipe(pipe_name, 200).unwrap();

        ns.write_pipe(pipe_name, b"cross-process data").unwrap();
        let data = ns.read_pipe(pipe_name, 1024).unwrap();
        assert_eq!(data, b"cross-process data");
    }

    #[test]
    fn pipe_double_connect_rejected() {
        let mut pipe = NamedPipe::create("test", PipeDirection::Duplex, 100);
        pipe.connect(200).unwrap();
        assert!(pipe.connect(300).is_err());
    }

    #[test]
    fn pipe_wrong_direction() {
        let mut pipe = NamedPipe::create("test", PipeDirection::In, 100);
        assert!(pipe.write(b"data").is_err());
    }

    #[test]
    fn pipe_not_found() {
        let mut ns = PipeNamespace::new();
        assert!(ns.connect_pipe("nonexistent", 100).is_err());
    }

    #[test]
    fn pipe_namespace_count() {
        let mut ns = PipeNamespace::new();
        ns.create_pipe("p1", PipeDirection::Duplex, 1).unwrap();
        ns.create_pipe("p2", PipeDirection::In, 2).unwrap();
        assert_eq!(ns.pipe_count(), 2);
    }

    // EventObject tests

    #[test]
    fn event_manual_reset_signal() {
        let mut event = EventObject::new("manual_evt", false);
        assert!(!event.signaled);
        let woken = event.signal();
        assert!(woken.is_empty());
        assert!(event.signaled);

        event.reset();
        assert!(!event.signaled);
    }

    #[test]
    fn event_auto_reset_signal() {
        let mut event = EventObject::new("auto_evt", true);
        event.wait(100);
        event.wait(200);
        assert_eq!(event.waiting_pids.len(), 2);

        let woken = event.signal();
        assert_eq!(woken, vec![100, 200]);
        assert!(!event.signaled);
    }

    #[test]
    fn event_wait_already_signaled() {
        let mut event = EventObject::new("pre_signaled", true);
        event.signal();
        assert!(event.wait(100));
        assert!(!event.signaled);
    }

    #[test]
    fn event_wait_not_signaled_queues() {
        let mut event = EventObject::new("not_ready", false);
        assert!(!event.wait(100));
        assert_eq!(event.waiting_pids, vec![100]);
    }

    #[test]
    fn event_wait_dedup() {
        let mut event = EventObject::new("dedup", false);
        event.wait(42);
        event.wait(42);
        assert_eq!(event.waiting_pids.len(), 1);
    }

    // EventNamespace tests

    #[test]
    fn event_namespace_create_and_open() {
        let mut ns = EventNamespace::new();
        let idx = ns.create_event("myevent", false).unwrap();
        let opened = ns.open_event("myevent").unwrap();
        assert_eq!(idx, opened);
    }

    #[test]
    fn event_namespace_duplicate_rejected() {
        let mut ns = EventNamespace::new();
        ns.create_event("dup", false).unwrap();
        assert!(ns.create_event("dup", true).is_err());
    }

    #[test]
    fn event_namespace_signal_and_wait() {
        let mut ns = EventNamespace::new();
        ns.create_event("sync", false).unwrap();

        let immediate = ns.wait_event("sync", 100).unwrap();
        assert!(!immediate);

        let woken = ns.signal_event("sync").unwrap();
        assert_eq!(woken, vec![100]);
    }

    #[test]
    fn event_namespace_close() {
        let mut ns = EventNamespace::new();
        ns.create_event("temp", false).unwrap();
        assert_eq!(ns.event_count(), 1);
        ns.close_event("temp").unwrap();
        assert_eq!(ns.event_count(), 0);
    }

    #[test]
    fn event_namespace_close_not_found() {
        let mut ns = EventNamespace::new();
        assert!(ns.close_event("ghost").is_err());
    }

    #[test]
    fn event_namespace_reset() {
        let mut ns = EventNamespace::new();
        ns.create_event("rst", false).unwrap();
        ns.signal_event("rst").unwrap();
        ns.reset_event("rst").unwrap();
        let immediate = ns.wait_event("rst", 1).unwrap();
        assert!(!immediate);
    }

    // AlpcPort tests

    #[test]
    fn alpc_port_connect_send_receive() {
        let mut port = AlpcPort::new("\\RPC Control\\TestPort", 1);
        port.connect(2).unwrap();

        let msg_id = port.send(2, b"request data").unwrap();
        assert_eq!(msg_id, 1);

        let msg = port.receive().unwrap();
        assert_eq!(msg.sender_pid, 2);
        assert_eq!(msg.data, b"request data");
    }

    #[test]
    fn alpc_port_server_can_send() {
        let mut port = AlpcPort::new("port", 10);
        port.connect(20).unwrap();
        assert!(port.send(10, b"response").is_ok());
    }

    #[test]
    fn alpc_port_unconnected_cannot_send() {
        let mut port = AlpcPort::new("port", 10);
        assert!(port.send(99, b"nope").is_err());
    }

    #[test]
    fn alpc_port_double_connect_rejected() {
        let mut port = AlpcPort::new("port", 10);
        port.connect(20).unwrap();
        assert!(port.connect(20).is_err());
    }

    #[test]
    fn alpc_port_disconnect() {
        let mut port = AlpcPort::new("port", 10);
        port.connect(20).unwrap();
        port.disconnect(20).unwrap();
        assert!(port.connected_clients.is_empty());
    }

    #[test]
    fn alpc_port_disconnect_not_connected() {
        let mut port = AlpcPort::new("port", 10);
        assert!(port.disconnect(99).is_err());
    }

    #[test]
    fn alpc_port_receive_empty() {
        let mut port = AlpcPort::new("port", 10);
        assert!(port.receive().is_err());
    }

    #[test]
    fn alpc_port_message_ordering() {
        let mut port = AlpcPort::new("port", 10);
        port.connect(20).unwrap();
        port.send(20, b"first").unwrap();
        port.send(20, b"second").unwrap();
        port.send(10, b"third").unwrap();

        assert_eq!(port.pending_message_count(), 3);
        assert_eq!(port.receive().unwrap().data, b"first");
        assert_eq!(port.receive().unwrap().data, b"second");
        assert_eq!(port.receive().unwrap().data, b"third");
    }

    // AlpcNamespace tests

    #[test]
    fn alpc_namespace_create_and_connect() {
        let mut ns = AlpcNamespace::new();
        ns.create_port("\\RPC\\Port1", 1).unwrap();
        ns.connect_port("\\RPC\\Port1", 2).unwrap();
        ns.send_message("\\RPC\\Port1", 2, b"hello").unwrap();
        let msg = ns.receive_message("\\RPC\\Port1").unwrap();
        assert_eq!(msg.data, b"hello");
    }

    #[test]
    fn alpc_namespace_duplicate_port_rejected() {
        let mut ns = AlpcNamespace::new();
        ns.create_port("p", 1).unwrap();
        assert!(ns.create_port("p", 2).is_err());
    }

    #[test]
    fn alpc_namespace_not_found() {
        let mut ns = AlpcNamespace::new();
        assert!(ns.connect_port("nope", 1).is_err());
        assert!(ns.send_message("nope", 1, b"x").is_err());
        assert!(ns.receive_message("nope").is_err());
    }

    // SessionIpcManager tests

    #[test]
    fn session_manager_integration() {
        let mut mgr = SessionIpcManager::new();
        assert_eq!(mgr.total_object_count(), 0);

        mgr.pipes.create_pipe("pipe1", PipeDirection::Duplex, 1).unwrap();
        mgr.shared_memory.create_section("shm1", 4096, 1).unwrap();
        mgr.events.create_event("evt1", false).unwrap();
        mgr.alpc.create_port("port1", 1).unwrap();

        assert_eq!(mgr.total_object_count(), 4);
    }

    #[test]
    fn session_manager_cross_subsystem() {
        let mut mgr = SessionIpcManager::new();

        mgr.events.create_event("data_ready", true).unwrap();
        mgr.shared_memory.create_section("buffer", 1024, 10).unwrap();

        mgr.shared_memory.write_section("buffer", 0, b"payload").unwrap();
        let woken = mgr.events.signal_event("data_ready").unwrap();
        assert!(woken.is_empty());

        mgr.events.wait_event("data_ready", 20).unwrap();
        mgr.events.signal_event("data_ready").unwrap();

        let data = mgr.shared_memory.read_section("buffer", 0, 7).unwrap();
        assert_eq!(data, b"payload");
    }

    #[test]
    fn session_manager_alpc_rpc_flow() {
        let mut mgr = SessionIpcManager::new();
        mgr.alpc.create_port("\\RPC\\AppService", 1).unwrap();
        mgr.alpc.connect_port("\\RPC\\AppService", 2).unwrap();

        mgr.alpc.send_message("\\RPC\\AppService", 2, b"GetVersion").unwrap();
        let req = mgr.alpc.receive_message("\\RPC\\AppService").unwrap();
        assert_eq!(req.data, b"GetVersion");

        mgr.alpc.send_message("\\RPC\\AppService", 1, b"v1.0").unwrap();
        let resp = mgr.alpc.receive_message("\\RPC\\AppService").unwrap();
        assert_eq!(resp.data, b"v1.0");
    }
}
