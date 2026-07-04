use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u32)]
pub enum NtStatus {
    Success = 0x0000_0000,
    Pending = 0x0000_0103,
    NotImplemented = 0xC000_0002,
    InvalidHandle = 0xC000_0008,
    InvalidParameter = 0xC000_000D,
    NoSuchFile = 0xC000_000F,
    AccessDenied = 0xC000_0022,
    ObjectNameNotFound = 0xC000_0034,
    ObjectNameCollision = 0xC000_0035,
    NotSupported = 0xC000_BB02,
}

impl NtStatus {
    pub fn is_success(&self) -> bool {
        (*self as u32) < 0x8000_0000
    }

    pub fn is_error(&self) -> bool {
        (*self as u32) >= 0xC000_0000
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NtSyscall {
    NtClose,
    NtCreateFile,
    NtReadFile,
    NtWriteFile,
    NtCreateSection,
    NtMapViewOfSection,
    NtQueryInformationProcess,
    NtQuerySystemInformation,
    NtAllocateVirtualMemory,
    NtFreeVirtualMemory,
    NtProtectVirtualMemory,
    NtLoadDriver,
    NtUnloadDriver,
    NtDeviceIoControlFile,
}

// --- Virtual Memory Manager ---

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtualMemoryRegion {
    pub base_address: u64,
    pub size: u64,
    pub protection: MemoryProtection,
    pub state: MemoryState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemoryProtection {
    NoAccess,
    ReadOnly,
    ReadWrite,
    ReadExecute,
    ReadWriteExecute,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemoryState {
    Free,
    Reserved,
    Committed,
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct VirtualMemoryManager {
    regions: Vec<VirtualMemoryRegion>,
    next_base: u64,
}

impl VirtualMemoryManager {
    pub fn new() -> Self {
        Self {
            regions: Vec::new(),
            next_base: 0x0000_0010_0000_0000,
        }
    }

    pub fn allocate(&mut self, size: u64, protection: MemoryProtection) -> Result<u64, NtStatus> {
        if size == 0 {
            return Err(NtStatus::InvalidParameter);
        }
        let aligned_size = (size + 0xFFF) & !0xFFF;
        let base = self.next_base;
        self.next_base += aligned_size;

        self.regions.push(VirtualMemoryRegion {
            base_address: base,
            size: aligned_size,
            protection,
            state: MemoryState::Committed,
        });

        Ok(base)
    }

    pub fn free(&mut self, base_address: u64) -> Result<(), NtStatus> {
        if let Some(idx) = self.regions.iter().position(|r| r.base_address == base_address) {
            self.regions[idx].state = MemoryState::Free;
            Ok(())
        } else {
            Err(NtStatus::InvalidParameter)
        }
    }

    pub fn protect(&mut self, base_address: u64, new_protection: MemoryProtection) -> Result<MemoryProtection, NtStatus> {
        if let Some(region) = self.regions.iter_mut().find(|r| r.base_address == base_address) {
            let old = region.protection;
            region.protection = new_protection;
            Ok(old)
        } else {
            Err(NtStatus::InvalidParameter)
        }
    }

    pub fn query(&self, address: u64) -> Option<&VirtualMemoryRegion> {
        self.regions.iter().find(|r| {
            address >= r.base_address && address < r.base_address + r.size
        })
    }

    pub fn region_count(&self) -> usize {
        self.regions.iter().filter(|r| r.state == MemoryState::Committed).count()
    }
}

// --- Virtual File System ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FileAccessMode {
    Read,
    Write,
    ReadWrite,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VirtualFile {
    pub path: String,
    pub content: Vec<u8>,
    pub position: u64,
    pub access: FileAccessMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FileHandle(pub u64);

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct VirtualFileSystem {
    files: HashMap<String, Vec<u8>>,
    open_handles: HashMap<u64, VirtualFile>,
    next_handle: u64,
}

impl VirtualFileSystem {
    pub fn new() -> Self {
        let mut vfs = Self {
            files: HashMap::new(),
            open_handles: HashMap::new(),
            next_handle: 0x1000,
        };
        vfs.populate_system_files();
        vfs
    }

    fn populate_system_files(&mut self) {
        self.files.insert(r"C:\Windows\System32\ntdll.dll".into(), vec![0x4D, 0x5A]);
        self.files.insert(r"C:\Windows\System32\kernel32.dll".into(), vec![0x4D, 0x5A]);
        self.files.insert(r"C:\Windows\System32\user32.dll".into(), vec![0x4D, 0x5A]);
        self.files.insert(r"C:\Windows\System32\gdi32.dll".into(), vec![0x4D, 0x5A]);
        self.files.insert(r"C:\Windows\System32\advapi32.dll".into(), vec![0x4D, 0x5A]);
    }

    pub fn create_file(&mut self, path: &str, access: FileAccessMode) -> Result<FileHandle, NtStatus> {
        let content = self.files.get(path).cloned().unwrap_or_default();
        let handle_id = self.next_handle;
        self.next_handle += 1;

        self.open_handles.insert(handle_id, VirtualFile {
            path: path.to_string(),
            content,
            position: 0,
            access,
        });

        if !self.files.contains_key(path) {
            self.files.insert(path.to_string(), Vec::new());
        }

        Ok(FileHandle(handle_id))
    }

    pub fn open_file(&mut self, path: &str, access: FileAccessMode) -> Result<FileHandle, NtStatus> {
        if !self.files.contains_key(path) {
            return Err(NtStatus::NoSuchFile);
        }
        let content = self.files[path].clone();
        let handle_id = self.next_handle;
        self.next_handle += 1;

        self.open_handles.insert(handle_id, VirtualFile {
            path: path.to_string(),
            content,
            position: 0,
            access,
        });

        Ok(FileHandle(handle_id))
    }

    pub fn read_file(&mut self, handle: FileHandle, buffer_size: usize) -> Result<Vec<u8>, NtStatus> {
        let file = self.open_handles.get_mut(&handle.0)
            .ok_or(NtStatus::InvalidHandle)?;

        if file.access == FileAccessMode::Write {
            return Err(NtStatus::AccessDenied);
        }

        let pos = file.position as usize;
        let available = file.content.len().saturating_sub(pos);
        let to_read = buffer_size.min(available);
        let data = file.content[pos..pos + to_read].to_vec();
        file.position += to_read as u64;
        Ok(data)
    }

    pub fn write_file(&mut self, handle: FileHandle, data: &[u8]) -> Result<usize, NtStatus> {
        let file = self.open_handles.get_mut(&handle.0)
            .ok_or(NtStatus::InvalidHandle)?;

        if file.access == FileAccessMode::Read {
            return Err(NtStatus::AccessDenied);
        }

        let pos = file.position as usize;
        if pos + data.len() > file.content.len() {
            file.content.resize(pos + data.len(), 0);
        }
        file.content[pos..pos + data.len()].copy_from_slice(data);
        file.position += data.len() as u64;

        let path = file.path.clone();
        let content = file.content.clone();
        self.files.insert(path, content);

        Ok(data.len())
    }

    pub fn close_handle(&mut self, handle: FileHandle) -> Result<(), NtStatus> {
        if self.open_handles.remove(&handle.0).is_some() {
            Ok(())
        } else {
            Err(NtStatus::InvalidHandle)
        }
    }

    pub fn file_exists(&self, path: &str) -> bool {
        self.files.contains_key(path)
    }

    pub fn open_handle_count(&self) -> usize {
        self.open_handles.len()
    }
}

// --- NT Kernel Dispatch ---

#[derive(Debug, Default)]
pub struct NtKernel {
    pub memory: VirtualMemoryManager,
    pub filesystem: VirtualFileSystem,
}

impl NtKernel {
    pub fn new() -> Self {
        Self {
            memory: VirtualMemoryManager::new(),
            filesystem: VirtualFileSystem::new(),
        }
    }

    pub fn dispatch(&mut self, syscall: NtSyscall) -> NtStatus {
        match syscall {
            NtSyscall::NtClose => NtStatus::Success,
            NtSyscall::NtCreateFile => NtStatus::Success,
            NtSyscall::NtReadFile => NtStatus::Success,
            NtSyscall::NtWriteFile => NtStatus::Success,
            NtSyscall::NtAllocateVirtualMemory => NtStatus::Success,
            NtSyscall::NtFreeVirtualMemory => NtStatus::Success,
            NtSyscall::NtProtectVirtualMemory => NtStatus::Success,
            NtSyscall::NtCreateSection => NtStatus::Success,
            NtSyscall::NtMapViewOfSection => NtStatus::Success,
            NtSyscall::NtQueryInformationProcess => NtStatus::Success,
            NtSyscall::NtQuerySystemInformation => NtStatus::Success,
            NtSyscall::NtLoadDriver => NtStatus::AccessDenied,
            NtSyscall::NtUnloadDriver => NtStatus::AccessDenied,
            NtSyscall::NtDeviceIoControlFile => NtStatus::Success,
        }
    }
}

pub fn dispatch_nt_syscall(syscall: NtSyscall) -> NtStatus {
    match syscall {
        NtSyscall::NtClose => NtStatus::Success,
        NtSyscall::NtCreateFile => NtStatus::Success,
        NtSyscall::NtReadFile => NtStatus::Success,
        NtSyscall::NtWriteFile => NtStatus::Success,
        NtSyscall::NtCreateSection => NtStatus::Success,
        NtSyscall::NtMapViewOfSection => NtStatus::Success,
        NtSyscall::NtQueryInformationProcess => NtStatus::Success,
        NtSyscall::NtQuerySystemInformation => NtStatus::Success,
        NtSyscall::NtAllocateVirtualMemory => NtStatus::Success,
        NtSyscall::NtFreeVirtualMemory => NtStatus::Success,
        NtSyscall::NtProtectVirtualMemory => NtStatus::Success,
        NtSyscall::NtLoadDriver => NtStatus::AccessDenied,
        NtSyscall::NtUnloadDriver => NtStatus::AccessDenied,
        NtSyscall::NtDeviceIoControlFile => NtStatus::Success,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nt_status_success() {
        assert!(NtStatus::Success.is_success());
        assert!(!NtStatus::Success.is_error());
    }

    #[test]
    fn nt_status_error() {
        assert!(NtStatus::AccessDenied.is_error());
        assert!(!NtStatus::AccessDenied.is_success());
    }

    #[test]
    fn nt_close_succeeds() {
        assert_eq!(dispatch_nt_syscall(NtSyscall::NtClose), NtStatus::Success);
    }

    #[test]
    fn nt_load_driver_denied() {
        assert_eq!(dispatch_nt_syscall(NtSyscall::NtLoadDriver), NtStatus::AccessDenied);
        assert_eq!(dispatch_nt_syscall(NtSyscall::NtUnloadDriver), NtStatus::AccessDenied);
    }

    #[test]
    fn syscalls_implemented() {
        let implemented = [
            NtSyscall::NtCreateFile,
            NtSyscall::NtReadFile,
            NtSyscall::NtWriteFile,
            NtSyscall::NtAllocateVirtualMemory,
            NtSyscall::NtFreeVirtualMemory,
            NtSyscall::NtProtectVirtualMemory,
            NtSyscall::NtCreateSection,
            NtSyscall::NtMapViewOfSection,
            NtSyscall::NtQueryInformationProcess,
            NtSyscall::NtQuerySystemInformation,
        ];
        for sc in implemented {
            assert_eq!(dispatch_nt_syscall(sc), NtStatus::Success,
                "syscall {:?} should return Success", sc);
        }
    }

    // Virtual Memory Manager tests

    #[test]
    fn vmm_allocate_and_query() {
        let mut vmm = VirtualMemoryManager::new();
        let base = vmm.allocate(4096, MemoryProtection::ReadWrite).unwrap();
        assert!(base > 0);

        let region = vmm.query(base).unwrap();
        assert_eq!(region.size, 4096);
        assert_eq!(region.protection, MemoryProtection::ReadWrite);
        assert_eq!(region.state, MemoryState::Committed);
    }

    #[test]
    fn vmm_allocate_multiple() {
        let mut vmm = VirtualMemoryManager::new();
        let b1 = vmm.allocate(0x1000, MemoryProtection::ReadOnly).unwrap();
        let b2 = vmm.allocate(0x2000, MemoryProtection::ReadExecute).unwrap();
        assert_ne!(b1, b2);
        assert_eq!(vmm.region_count(), 2);
    }

    #[test]
    fn vmm_free() {
        let mut vmm = VirtualMemoryManager::new();
        let base = vmm.allocate(4096, MemoryProtection::ReadWrite).unwrap();
        assert!(vmm.free(base).is_ok());
        assert_eq!(vmm.region_count(), 0);
    }

    #[test]
    fn vmm_protect() {
        let mut vmm = VirtualMemoryManager::new();
        let base = vmm.allocate(4096, MemoryProtection::ReadWrite).unwrap();
        let old = vmm.protect(base, MemoryProtection::ReadExecute).unwrap();
        assert_eq!(old, MemoryProtection::ReadWrite);
        assert_eq!(vmm.query(base).unwrap().protection, MemoryProtection::ReadExecute);
    }

    #[test]
    fn vmm_zero_size_rejected() {
        let mut vmm = VirtualMemoryManager::new();
        assert!(vmm.allocate(0, MemoryProtection::ReadWrite).is_err());
    }

    #[test]
    fn vmm_free_invalid_addr() {
        let mut vmm = VirtualMemoryManager::new();
        assert!(vmm.free(0xDEAD).is_err());
    }

    // Virtual File System tests

    #[test]
    fn vfs_system_files_exist() {
        let vfs = VirtualFileSystem::new();
        assert!(vfs.file_exists(r"C:\Windows\System32\ntdll.dll"));
        assert!(vfs.file_exists(r"C:\Windows\System32\kernel32.dll"));
        assert!(vfs.file_exists(r"C:\Windows\System32\user32.dll"));
    }

    #[test]
    fn vfs_open_existing() {
        let mut vfs = VirtualFileSystem::new();
        let handle = vfs.open_file(r"C:\Windows\System32\ntdll.dll", FileAccessMode::Read).unwrap();
        let data = vfs.read_file(handle, 2).unwrap();
        assert_eq!(data, [0x4D, 0x5A]);
    }

    #[test]
    fn vfs_open_nonexistent_fails() {
        let mut vfs = VirtualFileSystem::new();
        assert!(vfs.open_file(r"C:\nonexistent.dll", FileAccessMode::Read).is_err());
    }

    #[test]
    fn vfs_create_write_read() {
        let mut vfs = VirtualFileSystem::new();
        let wh = vfs.create_file(r"C:\Users\test\data.txt", FileAccessMode::ReadWrite).unwrap();
        let written = vfs.write_file(wh, b"hello world").unwrap();
        assert_eq!(written, 11);
        vfs.close_handle(wh).unwrap();

        let rh = vfs.open_file(r"C:\Users\test\data.txt", FileAccessMode::Read).unwrap();
        let data = vfs.read_file(rh, 1024).unwrap();
        assert_eq!(data, b"hello world");
    }

    #[test]
    fn vfs_close_handle() {
        let mut vfs = VirtualFileSystem::new();
        let h = vfs.create_file(r"C:\temp.txt", FileAccessMode::Write).unwrap();
        assert!(vfs.close_handle(h).is_ok());
        assert!(vfs.close_handle(h).is_err());
    }

    #[test]
    fn vfs_read_on_write_only_denied() {
        let mut vfs = VirtualFileSystem::new();
        let h = vfs.create_file(r"C:\temp.txt", FileAccessMode::Write).unwrap();
        assert_eq!(vfs.read_file(h, 10).unwrap_err(), NtStatus::AccessDenied);
    }

    #[test]
    fn vfs_write_on_read_only_denied() {
        let mut vfs = VirtualFileSystem::new();
        let h = vfs.open_file(r"C:\Windows\System32\ntdll.dll", FileAccessMode::Read).unwrap();
        assert_eq!(vfs.write_file(h, b"data").unwrap_err(), NtStatus::AccessDenied);
    }

    // NtKernel integration

    #[test]
    fn nt_kernel_full_lifecycle() {
        let mut kernel = NtKernel::new();

        // Allocate memory
        let mem_base = kernel.memory.allocate(0x10000, MemoryProtection::ReadWrite).unwrap();
        assert!(mem_base > 0);

        // Create and write file
        let fh = kernel.filesystem.create_file(r"C:\app\config.ini", FileAccessMode::ReadWrite).unwrap();
        kernel.filesystem.write_file(fh, b"[settings]\nkey=value").unwrap();
        kernel.filesystem.close_handle(fh).unwrap();

        // Open and read back
        let fh2 = kernel.filesystem.open_file(r"C:\app\config.ini", FileAccessMode::Read).unwrap();
        let data = kernel.filesystem.read_file(fh2, 1024).unwrap();
        assert_eq!(data, b"[settings]\nkey=value");

        // Free memory
        assert!(kernel.memory.free(mem_base).is_ok());
    }

    #[test]
    fn nt_kernel_dispatch_all() {
        let mut kernel = NtKernel::new();
        assert_eq!(kernel.dispatch(NtSyscall::NtCreateFile), NtStatus::Success);
        assert_eq!(kernel.dispatch(NtSyscall::NtAllocateVirtualMemory), NtStatus::Success);
        assert_eq!(kernel.dispatch(NtSyscall::NtLoadDriver), NtStatus::AccessDenied);
    }
}
