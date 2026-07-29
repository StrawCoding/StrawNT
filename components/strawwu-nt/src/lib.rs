pub mod pe;
pub mod teb;
pub mod ntdll;
pub mod win32_stubs;
pub mod wow64;
pub mod ipc;
pub mod installer;
pub mod registry;
pub mod loader;
pub mod cpu;

pub use pe::{
    PeFile, PeMachine, PeSubsystem, ImportEntry, build_real_console_fixture_pe,
    build_win32_console_mvp_pe,
};
pub use teb::{ThreadEnvironmentBlock, ProcessEnvironmentBlock, LoadedModule};
pub use ntdll::{NtStatus, NtKernel, VirtualMemoryManager, VirtualFileSystem, FileHandle};
pub use wow64::Wow64Context;
pub use loader::PeLoader;
pub use cpu::{
    run_entry, CpuHaltReason, CpuRunResult, ExecSideEffects, STUB_BASE, STUB_EXIT_PROCESS,
    STUB_GET_STD_HANDLE, STUB_WRITE_FILE,
};
