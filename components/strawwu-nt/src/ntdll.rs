use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u32)]
pub enum NtStatus {
    Success = 0x0000_0000,
    NotImplemented = 0xC000_0002,
    InvalidHandle = 0xC000_0008,
    InvalidParameter = 0xC000_000D,
    AccessDenied = 0xC000_0022,
    ObjectNameNotFound = 0xC000_0034,
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

pub fn dispatch_nt_syscall(syscall: NtSyscall) -> NtStatus {
    match syscall {
        NtSyscall::NtClose => NtStatus::Success,
        NtSyscall::NtCreateFile => NtStatus::NotImplemented,
        NtSyscall::NtReadFile => NtStatus::NotImplemented,
        NtSyscall::NtWriteFile => NtStatus::NotImplemented,
        NtSyscall::NtCreateSection => NtStatus::NotImplemented,
        NtSyscall::NtMapViewOfSection => NtStatus::NotImplemented,
        NtSyscall::NtQueryInformationProcess => NtStatus::NotImplemented,
        NtSyscall::NtQuerySystemInformation => NtStatus::NotImplemented,
        NtSyscall::NtAllocateVirtualMemory => NtStatus::NotImplemented,
        NtSyscall::NtFreeVirtualMemory => NtStatus::NotImplemented,
        NtSyscall::NtProtectVirtualMemory => NtStatus::NotImplemented,
        NtSyscall::NtLoadDriver => NtStatus::AccessDenied,
        NtSyscall::NtUnloadDriver => NtStatus::AccessDenied,
        NtSyscall::NtDeviceIoControlFile => NtStatus::NotImplemented,
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
    fn unimplemented_syscalls() {
        let stubs = [
            NtSyscall::NtCreateFile,
            NtSyscall::NtReadFile,
            NtSyscall::NtWriteFile,
            NtSyscall::NtAllocateVirtualMemory,
        ];
        for sc in stubs {
            assert_eq!(dispatch_nt_syscall(sc), NtStatus::NotImplemented);
        }
    }
}
