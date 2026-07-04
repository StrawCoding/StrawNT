use serde::{Deserialize, Serialize};

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
}
