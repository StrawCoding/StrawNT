use serde::{Deserialize, Serialize};

const MZ_MAGIC: [u8; 2] = [0x4D, 0x5A];
const PE_SIGNATURE: [u8; 4] = [0x50, 0x45, 0x00, 0x00]; // "PE\0\0"

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u16)]
pub enum PeMachine {
    Unknown = 0x0000,
    I386 = 0x014C,
    Amd64 = 0x8664,
    Arm64 = 0xAA64,
}

impl PeMachine {
    pub fn from_u16(v: u16) -> Self {
        match v {
            0x014C => Self::I386,
            0x8664 => Self::Amd64,
            0xAA64 => Self::Arm64,
            _ => Self::Unknown,
        }
    }

    pub fn is_32bit(&self) -> bool {
        matches!(self, Self::I386)
    }

    pub fn is_64bit(&self) -> bool {
        matches!(self, Self::Amd64 | Self::Arm64)
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::I386 => "i386",
            Self::Amd64 => "amd64",
            Self::Arm64 => "arm64",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u16)]
pub enum PeSubsystem {
    Unknown = 0,
    Native = 1,
    WindowsGui = 2,
    WindowsCui = 3,
}

impl PeSubsystem {
    pub fn from_u16(v: u16) -> Self {
        match v {
            1 => Self::Native,
            2 => Self::WindowsGui,
            3 => Self::WindowsCui,
            _ => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeSection {
    pub name: String,
    pub virtual_address: u32,
    pub virtual_size: u32,
    pub raw_offset: u32,
    pub raw_size: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportEntry {
    pub dll_name: String,
    pub functions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeFile {
    pub machine: PeMachine,
    pub subsystem: PeSubsystem,
    pub entry_point: u32,
    pub image_base: u64,
    pub sections: Vec<PeSection>,
    pub imports: Vec<ImportEntry>,
    pub is_dll: bool,
    pub is_valid: bool,
}

impl PeFile {
    pub fn parse(data: &[u8]) -> Result<Self, PeError> {
        if data.len() < 64 {
            return Err(PeError::TooSmall);
        }
        if data[0..2] != MZ_MAGIC {
            return Err(PeError::InvalidMzSignature);
        }

        let pe_offset = u32::from_le_bytes(
            data[0x3C..0x40].try_into().map_err(|_| PeError::TooSmall)?,
        ) as usize;

        if data.len() < pe_offset + 4 {
            return Err(PeError::TooSmall);
        }
        if data[pe_offset..pe_offset + 4] != PE_SIGNATURE {
            return Err(PeError::InvalidPeSignature);
        }

        let coff_start = pe_offset + 4;
        if data.len() < coff_start + 20 {
            return Err(PeError::TooSmall);
        }

        let machine_raw = u16::from_le_bytes(
            data[coff_start..coff_start + 2].try_into().unwrap(),
        );
        let machine = PeMachine::from_u16(machine_raw);
        let num_sections = u16::from_le_bytes(
            data[coff_start + 2..coff_start + 4].try_into().unwrap(),
        ) as usize;
        let characteristics = u16::from_le_bytes(
            data[coff_start + 18..coff_start + 20].try_into().unwrap(),
        );
        let is_dll = (characteristics & 0x2000) != 0;
        let opt_header_size = u16::from_le_bytes(
            data[coff_start + 16..coff_start + 18].try_into().unwrap(),
        ) as usize;

        let opt_start = coff_start + 20;
        if data.len() < opt_start + opt_header_size.min(28) {
            return Err(PeError::TooSmall);
        }

        let magic = u16::from_le_bytes(
            data[opt_start..opt_start + 2].try_into().unwrap(),
        );
        let is_pe32_plus = magic == 0x020B;

        let entry_point = u32::from_le_bytes(
            data[opt_start + 16..opt_start + 20].try_into().unwrap(),
        );

        let image_base = if is_pe32_plus && data.len() >= opt_start + 32 {
            u64::from_le_bytes(
                data[opt_start + 24..opt_start + 32].try_into().unwrap(),
            )
        } else if data.len() >= opt_start + 32 {
            u32::from_le_bytes(
                data[opt_start + 28..opt_start + 32].try_into().unwrap(),
            ) as u64
        } else {
            0x0040_0000
        };

        let subsystem_offset = if is_pe32_plus { 68 } else { 68 };
        let subsystem = if data.len() >= opt_start + subsystem_offset + 2 {
            PeSubsystem::from_u16(u16::from_le_bytes(
                data[opt_start + subsystem_offset..opt_start + subsystem_offset + 2]
                    .try_into()
                    .unwrap(),
            ))
        } else {
            PeSubsystem::Unknown
        };

        let section_start = opt_start + opt_header_size;
        let mut sections = Vec::with_capacity(num_sections);
        for i in 0..num_sections {
            let off = section_start + i * 40;
            if data.len() < off + 40 {
                break;
            }
            let name_bytes = &data[off..off + 8];
            let name = String::from_utf8_lossy(
                &name_bytes[..name_bytes.iter().position(|&b| b == 0).unwrap_or(8)],
            ).to_string();
            sections.push(PeSection {
                name,
                virtual_size: u32::from_le_bytes(data[off + 8..off + 12].try_into().unwrap()),
                virtual_address: u32::from_le_bytes(data[off + 12..off + 16].try_into().unwrap()),
                raw_size: u32::from_le_bytes(data[off + 16..off + 20].try_into().unwrap()),
                raw_offset: u32::from_le_bytes(data[off + 20..off + 24].try_into().unwrap()),
            });
        }

        let imports = Self::parse_imports(data, opt_start, is_pe32_plus, &sections);

        Ok(Self {
            machine,
            subsystem,
            entry_point,
            image_base,
            sections,
            imports,
            is_dll,
            is_valid: true,
        })
    }

    fn parse_imports(data: &[u8], opt_start: usize, is_pe32_plus: bool, sections: &[PeSection]) -> Vec<ImportEntry> {
        let dd_offset = if is_pe32_plus { opt_start + 120 } else { opt_start + 104 };
        if data.len() < dd_offset + 8 {
            return Vec::new();
        }

        let import_rva = u32::from_le_bytes(
            data[dd_offset..dd_offset + 4].try_into().unwrap_or([0; 4]),
        );
        let import_size = u32::from_le_bytes(
            data[dd_offset + 4..dd_offset + 8].try_into().unwrap_or([0; 4]),
        );

        if import_rva == 0 || import_size == 0 {
            return Vec::new();
        }

        let import_file_offset = match Self::rva_to_file_offset(import_rva, sections) {
            Some(off) => off,
            None => return Vec::new(),
        };

        let mut imports = Vec::new();
        let mut desc_offset = import_file_offset;

        loop {
            if data.len() < desc_offset + 20 {
                break;
            }

            let name_rva = u32::from_le_bytes(
                data[desc_offset + 12..desc_offset + 16].try_into().unwrap_or([0; 4]),
            );
            let ilt_rva = u32::from_le_bytes(
                data[desc_offset..desc_offset + 4].try_into().unwrap_or([0; 4]),
            );

            if name_rva == 0 && ilt_rva == 0 {
                break;
            }

            let dll_name = if let Some(name_off) = Self::rva_to_file_offset(name_rva, sections) {
                Self::read_cstring(data, name_off)
            } else {
                String::new()
            };

            let functions = if let Some(ilt_off) = Self::rva_to_file_offset(ilt_rva, sections) {
                Self::parse_ilt(data, ilt_off, is_pe32_plus, sections)
            } else {
                Vec::new()
            };

            if !dll_name.is_empty() {
                imports.push(ImportEntry { dll_name, functions });
            }

            desc_offset += 20;
        }

        imports
    }

    fn rva_to_file_offset(rva: u32, sections: &[PeSection]) -> Option<usize> {
        // Compute in u64 so a crafted section with a large virtual_address/size
        // cannot overflow u32 and wrap into a bogus (but in-range) offset.
        let rva = rva as u64;
        for section in sections {
            let sec_start = section.virtual_address as u64;
            let sec_end = sec_start + section.virtual_size.max(section.raw_size) as u64;
            if rva >= sec_start && rva < sec_end {
                return Some((rva - sec_start + section.raw_offset as u64) as usize);
            }
        }
        None
    }

    fn parse_ilt(data: &[u8], mut offset: usize, is_pe32_plus: bool, sections: &[PeSection]) -> Vec<String> {
        let entry_size = if is_pe32_plus { 8 } else { 4 };
        let mut functions = Vec::new();

        loop {
            if data.len() < offset + entry_size {
                break;
            }

            let entry = if is_pe32_plus {
                u64::from_le_bytes(data[offset..offset + 8].try_into().unwrap_or([0; 8]))
            } else {
                u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap_or([0; 4])) as u64
            };

            if entry == 0 {
                break;
            }

            let ordinal_flag = if is_pe32_plus { 1u64 << 63 } else { 1u64 << 31 };
            if entry & ordinal_flag != 0 {
                functions.push(format!("ordinal#{}", entry & 0xFFFF));
            } else {
                let hint_rva = (entry & 0x7FFF_FFFF) as u32;
                if let Some(hint_off) = Self::rva_to_file_offset(hint_rva, sections) {
                    if data.len() > hint_off + 2 {
                        let name = Self::read_cstring(data, hint_off + 2);
                        if !name.is_empty() {
                            functions.push(name);
                        }
                    }
                }
            }

            offset += entry_size;
        }

        functions
    }

    fn read_cstring(data: &[u8], offset: usize) -> String {
        let mut end = offset;
        while end < data.len() && data[end] != 0 {
            end += 1;
        }
        String::from_utf8_lossy(&data[offset..end]).to_string()
    }

    pub fn needs_wow64(&self) -> bool {
        self.machine.is_32bit()
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum PeError {
    #[error("data too small for PE parsing")]
    TooSmall,
    #[error("invalid MZ signature")]
    InvalidMzSignature,
    #[error("invalid PE signature")]
    InvalidPeSignature,
}

pub fn build_stub_pe(machine: PeMachine, subsystem: PeSubsystem) -> Vec<u8> {
    let mut pe = vec![0u8; 512];
    pe[0] = 0x4D;
    pe[1] = 0x5A; // MZ
    pe[0x3C..0x40].copy_from_slice(&80u32.to_le_bytes()); // PE offset at 0x50

    let pe_off = 80usize;
    pe[pe_off..pe_off + 4].copy_from_slice(&PE_SIGNATURE);

    let coff = pe_off + 4;
    pe[coff..coff + 2].copy_from_slice(&(machine as u16).to_le_bytes());
    pe[coff + 2..coff + 4].copy_from_slice(&1u16.to_le_bytes()); // 1 section
    pe[coff + 16..coff + 18].copy_from_slice(&112u16.to_le_bytes()); // optional header size

    let opt = coff + 20;
    let magic: u16 = if machine.is_64bit() { 0x020B } else { 0x010B };
    pe[opt..opt + 2].copy_from_slice(&magic.to_le_bytes());
    pe[opt + 16..opt + 20].copy_from_slice(&0x1000u32.to_le_bytes()); // entry point
    if machine.is_64bit() {
        pe[opt + 24..opt + 32].copy_from_slice(&0x0000_0001_4000_0000u64.to_le_bytes());
    } else {
        pe[opt + 28..opt + 32].copy_from_slice(&0x0040_0000u32.to_le_bytes());
    }
    pe[opt + 68..opt + 70].copy_from_slice(&(subsystem as u16).to_le_bytes());

    let sec = opt + 112;
    pe[sec..sec + 5].copy_from_slice(b".text");
    pe[sec + 8..sec + 12].copy_from_slice(&0x1000u32.to_le_bytes()); // virtual size
    pe[sec + 12..sec + 16].copy_from_slice(&0x1000u32.to_le_bytes()); // virtual addr
    pe[sec + 16..sec + 20].copy_from_slice(&0x200u32.to_le_bytes());  // raw size
    pe[sec + 20..sec + 24].copy_from_slice(&0x200u32.to_le_bytes());  // raw offset

    pe
}

/// Build a PE with a populated import table for testing import resolution
pub fn build_pe_with_imports(machine: PeMachine, subsystem: PeSubsystem, dll_imports: &[(&str, &[&str])]) -> Vec<u8> {
    let is_64 = machine.is_64bit();
    let entry_size: usize = if is_64 { 8 } else { 4 };

    let mut pe = vec![0u8; 4096];
    pe[0] = 0x4D;
    pe[1] = 0x5A;
    pe[0x3C..0x40].copy_from_slice(&80u32.to_le_bytes());

    let pe_off = 80usize;
    pe[pe_off..pe_off + 4].copy_from_slice(&PE_SIGNATURE);

    let coff = pe_off + 4;
    pe[coff..coff + 2].copy_from_slice(&(machine as u16).to_le_bytes());
    pe[coff + 2..coff + 4].copy_from_slice(&2u16.to_le_bytes()); // 2 sections
    let opt_header_size: u16 = if is_64 { 240 } else { 224 };
    pe[coff + 16..coff + 18].copy_from_slice(&opt_header_size.to_le_bytes());

    let opt = coff + 20;
    let magic: u16 = if is_64 { 0x020B } else { 0x010B };
    pe[opt..opt + 2].copy_from_slice(&magic.to_le_bytes());
    pe[opt + 16..opt + 20].copy_from_slice(&0x1000u32.to_le_bytes());
    if is_64 {
        pe[opt + 24..opt + 32].copy_from_slice(&0x0000_0001_4000_0000u64.to_le_bytes());
    } else {
        pe[opt + 28..opt + 32].copy_from_slice(&0x0040_0000u32.to_le_bytes());
    }
    pe[opt + 68..opt + 70].copy_from_slice(&(subsystem as u16).to_le_bytes());

    // Number of RVA and sizes (16)
    let num_dd_offset = if is_64 { opt + 108 } else { opt + 92 };
    pe[num_dd_offset..num_dd_offset + 4].copy_from_slice(&16u32.to_le_bytes());

    // Section headers start after optional header
    let sec_start = opt + opt_header_size as usize;

    // .text section at RVA 0x1000, file offset 0x400
    pe[sec_start..sec_start + 5].copy_from_slice(b".text");
    pe[sec_start + 8..sec_start + 12].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec_start + 12..sec_start + 16].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec_start + 16..sec_start + 20].copy_from_slice(&0x200u32.to_le_bytes());
    pe[sec_start + 20..sec_start + 24].copy_from_slice(&0x400u32.to_le_bytes());

    // .idata section at RVA 0x2000, file offset 0x600
    let sec2 = sec_start + 40;
    pe[sec2..sec2 + 6].copy_from_slice(b".idata");
    pe[sec2 + 8..sec2 + 12].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec2 + 12..sec2 + 16].copy_from_slice(&0x2000u32.to_le_bytes());
    pe[sec2 + 16..sec2 + 20].copy_from_slice(&0x800u32.to_le_bytes());
    pe[sec2 + 20..sec2 + 24].copy_from_slice(&0x600u32.to_le_bytes());

    // Import directory data directory entry: RVA=0x2000, size=enough
    let dd_import_offset = if is_64 { opt + 120 } else { opt + 104 };
    pe[dd_import_offset..dd_import_offset + 4].copy_from_slice(&0x2000u32.to_le_bytes());
    let import_size = ((dll_imports.len() + 1) * 20) as u32;
    pe[dd_import_offset + 4..dd_import_offset + 8].copy_from_slice(&import_size.to_le_bytes());

    // Build import data in .idata (file offset 0x600, RVA 0x2000)
    let idata_base: usize = 0x600;
    let idata_rva_base: u32 = 0x2000;

    // Import descriptors start at idata_base
    let descs_size = (dll_imports.len() + 1) * 20;
    let mut string_pool_offset = idata_base + descs_size;
    let mut ilt_offset = string_pool_offset + 512; // leave room for strings

    for (i, (dll_name, funcs)) in dll_imports.iter().enumerate() {
        let desc_off = idata_base + i * 20;

        // Write ILT RVA
        let ilt_rva = idata_rva_base + (ilt_offset - idata_base) as u32;
        pe[desc_off..desc_off + 4].copy_from_slice(&ilt_rva.to_le_bytes());

        // Write DLL name RVA
        let name_rva = idata_rva_base + (string_pool_offset - idata_base) as u32;
        pe[desc_off + 12..desc_off + 16].copy_from_slice(&name_rva.to_le_bytes());

        // Write DLL name string
        let name_bytes = dll_name.as_bytes();
        pe[string_pool_offset..string_pool_offset + name_bytes.len()].copy_from_slice(name_bytes);
        pe[string_pool_offset + name_bytes.len()] = 0;
        string_pool_offset += name_bytes.len() + 1;

        // Write ILT entries for each function
        for func_name in *funcs {
            // Hint/Name entry: 2-byte hint (0) + name string
            let hint_name_rva = idata_rva_base + (string_pool_offset - idata_base) as u32;
            pe[string_pool_offset] = 0; // hint low
            pe[string_pool_offset + 1] = 0; // hint high
            let fn_bytes = func_name.as_bytes();
            pe[string_pool_offset + 2..string_pool_offset + 2 + fn_bytes.len()].copy_from_slice(fn_bytes);
            pe[string_pool_offset + 2 + fn_bytes.len()] = 0;
            string_pool_offset += 2 + fn_bytes.len() + 1;

            // ILT entry points to hint/name
            if is_64 {
                pe[ilt_offset..ilt_offset + 8].copy_from_slice(&(hint_name_rva as u64).to_le_bytes());
            } else {
                pe[ilt_offset..ilt_offset + 4].copy_from_slice(&hint_name_rva.to_le_bytes());
            }
            ilt_offset += entry_size;
        }

        // Null terminator for ILT
        ilt_offset += entry_size;
    }

    // Null terminator descriptor (already zeros)

    pe
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_stub_pe64() {
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.machine, PeMachine::Amd64);
        assert!(pe.machine.is_64bit());
        assert!(!pe.needs_wow64());
        assert_eq!(pe.entry_point, 0x1000);
        assert!(!pe.is_dll);
        assert_eq!(pe.sections.len(), 1);
        assert_eq!(pe.sections[0].name, ".text");
    }

    #[test]
    fn parse_stub_pe32() {
        let data = build_stub_pe(PeMachine::I386, PeSubsystem::WindowsCui);
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.machine, PeMachine::I386);
        assert!(pe.machine.is_32bit());
        assert!(pe.needs_wow64());
    }

    #[test]
    fn invalid_mz_rejected() {
        let data = vec![0x00; 512];
        assert!(PeFile::parse(&data).is_err());
    }

    #[test]
    fn too_small_rejected() {
        let data = vec![0x4D, 0x5A];
        assert!(PeFile::parse(&data).is_err());
    }

    #[test]
    fn machine_types() {
        assert!(PeMachine::I386.is_32bit());
        assert!(PeMachine::Amd64.is_64bit());
        assert!(PeMachine::Arm64.is_64bit());
        assert_eq!(PeMachine::from_u16(0x014C), PeMachine::I386);
        assert_eq!(PeMachine::from_u16(0x8664), PeMachine::Amd64);
        assert_eq!(PeMachine::from_u16(0x9999), PeMachine::Unknown);
    }

    #[test]
    fn parse_pe_with_imports_64() {
        let data = build_pe_with_imports(
            PeMachine::Amd64,
            PeSubsystem::WindowsGui,
            &[
                ("kernel32.dll", &["GetLastError", "SetLastError", "ExitProcess"]),
                ("user32.dll", &["MessageBoxW", "CreateWindowExW"]),
            ],
        );
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.imports.len(), 2);
        assert_eq!(pe.imports[0].dll_name, "kernel32.dll");
        assert_eq!(pe.imports[0].functions.len(), 3);
        assert!(pe.imports[0].functions.contains(&"GetLastError".to_string()));
        assert!(pe.imports[0].functions.contains(&"ExitProcess".to_string()));
        assert_eq!(pe.imports[1].dll_name, "user32.dll");
        assert_eq!(pe.imports[1].functions.len(), 2);
        assert!(pe.imports[1].functions.contains(&"MessageBoxW".to_string()));
    }

    #[test]
    fn parse_pe_with_imports_32() {
        let data = build_pe_with_imports(
            PeMachine::I386,
            PeSubsystem::WindowsCui,
            &[("msvcrt.dll", &["printf", "malloc", "free"])],
        );
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.imports.len(), 1);
        assert_eq!(pe.imports[0].dll_name, "msvcrt.dll");
        assert_eq!(pe.imports[0].functions.len(), 3);
        assert!(pe.imports[0].functions.contains(&"printf".to_string()));
    }

    #[test]
    fn pe_no_imports_still_works() {
        let data = build_stub_pe(PeMachine::Amd64, PeSubsystem::WindowsGui);
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.imports.is_empty());
    }

    #[test]
    fn real_console_fixture_parses_as_amd64_cui() {
        let data = build_real_console_fixture_pe();
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.machine, PeMachine::Amd64);
        assert_eq!(pe.subsystem, PeSubsystem::WindowsCui);
        assert_eq!(pe.entry_point, 0x1000);
        assert!(!pe.sections.is_empty());
    }

    #[test]
    fn win32_console_mvp_fixture_parses_as_amd64_cui() {
        let data = build_win32_console_mvp_pe();
        let pe = PeFile::parse(&data).unwrap();
        assert!(pe.is_valid);
        assert_eq!(pe.machine, PeMachine::Amd64);
        assert_eq!(pe.subsystem, PeSubsystem::WindowsCui);
        assert_eq!(pe.entry_point, 0x1000);
    }
}

/// Minimal AMD64 console PE with real x86-64 opcodes that call fixed
/// strawwu-nt stubs (GetStdHandle / WriteFile / ExitProcess) to emit
/// the observable marker `STRAWWU_PE_REAL_OK`.
pub fn build_real_console_fixture_pe() -> Vec<u8> {
    use crate::cpu::{STUB_EXIT_PROCESS, STUB_GET_STD_HANDLE, STUB_WRITE_FILE};

    let mut pe = vec![0u8; 0x800];
    pe[0] = 0x4D;
    pe[1] = 0x5A;
    pe[0x3C..0x40].copy_from_slice(&0x50u32.to_le_bytes());

    let pe_off = 0x50usize;
    pe[pe_off..pe_off + 4].copy_from_slice(&PE_SIGNATURE);

    let coff = pe_off + 4;
    pe[coff..coff + 2].copy_from_slice(&(PeMachine::Amd64 as u16).to_le_bytes());
    pe[coff + 2..coff + 4].copy_from_slice(&1u16.to_le_bytes());
    pe[coff + 16..coff + 18].copy_from_slice(&240u16.to_le_bytes());
    pe[coff + 18..coff + 20].copy_from_slice(&0x0022u16.to_le_bytes());

    let opt = coff + 20;
    pe[opt..opt + 2].copy_from_slice(&0x020Bu16.to_le_bytes());
    pe[opt + 16..opt + 20].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[opt + 24..opt + 32].copy_from_slice(&0x0000_0001_4000_0000u64.to_le_bytes());
    pe[opt + 32..opt + 36].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[opt + 36..opt + 40].copy_from_slice(&0x200u32.to_le_bytes());
    pe[opt + 56..opt + 60].copy_from_slice(&0x3000u32.to_le_bytes());
    pe[opt + 60..opt + 64].copy_from_slice(&0x200u32.to_le_bytes());
    pe[opt + 68..opt + 70].copy_from_slice(&(PeSubsystem::WindowsCui as u16).to_le_bytes());
    pe[opt + 108..opt + 112].copy_from_slice(&16u32.to_le_bytes());

    let sec = opt + 240;
    pe[sec..sec + 5].copy_from_slice(b".text");
    pe[sec + 8..sec + 12].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec + 12..sec + 16].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec + 16..sec + 20].copy_from_slice(&0x400u32.to_le_bytes());
    pe[sec + 20..sec + 24].copy_from_slice(&0x200u32.to_le_bytes());
    pe[sec + 36..sec + 40].copy_from_slice(&0x6000_0020u32.to_le_bytes());

    let text = 0x200usize;
    let msg = b"STRAWWU_PE_REAL_OK\n";
    // Code ends at offset 83 within .text; message + written follow.
    let msg_off = 83usize;
    let written_off = msg_off + msg.len();

    let mut o = text;
    // sub rsp, 0x28
    pe[o..o + 4].copy_from_slice(&[0x48, 0x83, 0xEC, 0x28]);
    o += 4;
    // mov ecx, -11
    pe[o..o + 5].copy_from_slice(&[0xB9, 0xF5, 0xFF, 0xFF, 0xFF]);
    o += 5;
    // mov rax, STUB_GET_STD_HANDLE
    pe[o] = 0x48;
    pe[o + 1] = 0xB8;
    pe[o + 2..o + 10].copy_from_slice(&STUB_GET_STD_HANDLE.to_le_bytes());
    o += 10;
    // call rax
    pe[o] = 0xFF;
    pe[o + 1] = 0xD0;
    o += 2;
    // mov rcx, rax
    pe[o..o + 3].copy_from_slice(&[0x48, 0x89, 0xC1]);
    o += 3;
    // lea rdx, [rip+msg]
    pe[o] = 0x48;
    pe[o + 1] = 0x8D;
    pe[o + 2] = 0x15;
    let lea_rdx_disp = (msg_off as i32) - ((o - text) as i32 + 7);
    pe[o + 3..o + 7].copy_from_slice(&lea_rdx_disp.to_le_bytes());
    o += 7;
    // mov r8d, 19
    pe[o..o + 6].copy_from_slice(&[0x41, 0xB8, 0x13, 0x00, 0x00, 0x00]);
    o += 6;
    // lea r9, [rip+written]
    pe[o] = 0x4C;
    pe[o + 1] = 0x8D;
    pe[o + 2] = 0x0D;
    let lea_r9_disp = (written_off as i32) - ((o - text) as i32 + 7);
    pe[o + 3..o + 7].copy_from_slice(&lea_r9_disp.to_le_bytes());
    o += 7;
    // mov qword [rsp+0x20], 0
    pe[o..o + 9].copy_from_slice(&[0x48, 0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x00]);
    o += 9;
    // mov rax, STUB_WRITE_FILE
    pe[o] = 0x48;
    pe[o + 1] = 0xB8;
    pe[o + 2..o + 10].copy_from_slice(&STUB_WRITE_FILE.to_le_bytes());
    o += 10;
    // call rax
    pe[o] = 0xFF;
    pe[o + 1] = 0xD0;
    o += 2;
    // add rsp, 0x28
    pe[o..o + 4].copy_from_slice(&[0x48, 0x83, 0xC4, 0x28]);
    o += 4;
    // xor ecx, ecx
    pe[o] = 0x31;
    pe[o + 1] = 0xC9;
    o += 2;
    // mov rax, STUB_EXIT_PROCESS
    pe[o] = 0x48;
    pe[o + 1] = 0xB8;
    pe[o + 2..o + 10].copy_from_slice(&STUB_EXIT_PROCESS.to_le_bytes());
    o += 10;
    // call rax
    pe[o] = 0xFF;
    pe[o + 1] = 0xD0;
    o += 2;

    debug_assert_eq!(o - text, msg_off);

    pe[text + msg_off..text + msg_off + msg.len()].copy_from_slice(msg);
    pe[text + written_off..text + written_off + 4].copy_from_slice(&0u32.to_le_bytes());

    pe
}

/// pe2 Win32 console MVP fixture: real x86-64 opcodes exercising kernel32
/// file/process APIs plus msvcrt CRT (malloc/puts/free) with host-observable
/// side effects — not registry-only stub checks.
pub fn build_win32_console_mvp_pe() -> Vec<u8> {
    use crate::cpu::{
        STUB_CLOSE_HANDLE, STUB_CREATE_FILE_A, STUB_EXIT_PROCESS, STUB_FREE,
        STUB_GET_COMMAND_LINE_A, STUB_GET_CURRENT_PROCESS_ID, STUB_GET_PROCESS_HEAP,
        STUB_GET_STD_HANDLE, STUB_HEAP_ALLOC, STUB_HEAP_FREE, STUB_MALLOC, STUB_PUTS,
        STUB_READ_FILE, STUB_WRITE_FILE,
    };

    let mut pe = vec![0u8; 0x1000];
    pe[0] = 0x4D;
    pe[1] = 0x5A;
    pe[0x3C..0x40].copy_from_slice(&0x50u32.to_le_bytes());

    let pe_off = 0x50usize;
    pe[pe_off..pe_off + 4].copy_from_slice(&PE_SIGNATURE);

    let coff = pe_off + 4;
    pe[coff..coff + 2].copy_from_slice(&(PeMachine::Amd64 as u16).to_le_bytes());
    pe[coff + 2..coff + 4].copy_from_slice(&1u16.to_le_bytes());
    pe[coff + 16..coff + 18].copy_from_slice(&240u16.to_le_bytes());
    pe[coff + 18..coff + 20].copy_from_slice(&0x0022u16.to_le_bytes());

    let opt = coff + 20;
    pe[opt..opt + 2].copy_from_slice(&0x020Bu16.to_le_bytes());
    pe[opt + 16..opt + 20].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[opt + 24..opt + 32].copy_from_slice(&0x0000_0001_4000_0000u64.to_le_bytes());
    pe[opt + 32..opt + 36].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[opt + 36..opt + 40].copy_from_slice(&0x200u32.to_le_bytes());
    pe[opt + 56..opt + 60].copy_from_slice(&0x4000u32.to_le_bytes());
    pe[opt + 60..opt + 64].copy_from_slice(&0x200u32.to_le_bytes());
    pe[opt + 68..opt + 70].copy_from_slice(&(PeSubsystem::WindowsCui as u16).to_le_bytes());
    pe[opt + 108..opt + 112].copy_from_slice(&16u32.to_le_bytes());

    let sec = opt + 240;
    pe[sec..sec + 5].copy_from_slice(b".text");
    pe[sec + 8..sec + 12].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec + 12..sec + 16].copy_from_slice(&0x1000u32.to_le_bytes());
    pe[sec + 16..sec + 20].copy_from_slice(&0x800u32.to_le_bytes());
    pe[sec + 20..sec + 24].copy_from_slice(&0x200u32.to_le_bytes());
    pe[sec + 36..sec + 40].copy_from_slice(&0x6000_0020u32.to_le_bytes());

    let text = 0x200usize;
    let marker = b"STRAWWU_PE_CONSOLE_OK\n";
    let crt_msg = b"STRAWWU_PE_CONSOLE_CRT\0";
    let filename = b"pe2-marker.txt\0";

    // Data placed at a fixed pad so LEA targets are known while assembling.
    let code_capacity = 512usize;
    let marker_off = code_capacity;
    let crt_off = marker_off + marker.len();
    let file_off = crt_off + crt_msg.len();
    let written_off = file_off + filename.len();

    let mut code: Vec<u8> = Vec::with_capacity(code_capacity);
    let emit = |code: &mut Vec<u8>, bytes: &[u8]| code.extend_from_slice(bytes);
    let emit_u64 = |code: &mut Vec<u8>, v: u64| {
        code.push(0x48);
        code.push(0xB8);
        code.extend_from_slice(&v.to_le_bytes());
    };
    let emit_call_rax = |code: &mut Vec<u8>| emit(code, &[0xFF, 0xD0]);
    let emit_lea = |code: &mut Vec<u8>, rex_reg: u8, modrm_reg: u8, target_off: usize| {
        code.push(rex_reg);
        code.push(0x8D);
        code.push(modrm_reg);
        let disp = (target_off as i32) - ((code.len() as i32) + 4);
        code.extend_from_slice(&disp.to_le_bytes());
    };

    // Assemble with known LEA targets at code_capacity.
    emit(&mut code, &[0x48, 0x83, 0xEC, 0x48]);

    // GetCurrentProcessId()
    emit_u64(&mut code, STUB_GET_CURRENT_PROCESS_ID);
    emit_call_rax(&mut code);

    // GetCommandLineA()
    emit_u64(&mut code, STUB_GET_COMMAND_LINE_A);
    emit_call_rax(&mut code);

    // GetProcessHeap(); HeapAlloc(heap, 0, 64)
    emit_u64(&mut code, STUB_GET_PROCESS_HEAP);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0xC1]); // mov rcx, rax
    emit(&mut code, &[0x31, 0xD2]); // xor edx, edx
    emit(&mut code, &[0x41, 0xB8, 0x40, 0x00, 0x00, 0x00]); // mov r8d, 64
    emit_u64(&mut code, STUB_HEAP_ALLOC);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0x44, 0x24, 0x30]); // mov [rsp+0x30], rax

    // malloc(64)
    emit(&mut code, &[0xB9, 0x40, 0x00, 0x00, 0x00]); // mov ecx, 64
    emit_u64(&mut code, STUB_MALLOC);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0x44, 0x24, 0x38]); // mov [rsp+0x38], rax

    // CreateFileA("pe2-marker.txt")
    emit_lea(&mut code, 0x48, 0x0D, file_off); // lea rcx
    emit_u64(&mut code, STUB_CREATE_FILE_A);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0x44, 0x24, 0x28]); // mov [rsp+0x28], rax

    // WriteFile(fh, marker, len, &written, NULL)
    emit(&mut code, &[0x48, 0x89, 0xC1]); // mov rcx, rax
    emit_lea(&mut code, 0x48, 0x15, marker_off); // lea rdx
    emit(
        &mut code,
        &[0x41, 0xB8, marker.len() as u8, 0x00, 0x00, 0x00],
    );
    emit_lea(&mut code, 0x4C, 0x0D, written_off); // lea r9
    emit(
        &mut code,
        &[0x48, 0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x00],
    );
    emit_u64(&mut code, STUB_WRITE_FILE);
    emit_call_rax(&mut code);

    // CloseHandle(fh)
    emit(&mut code, &[0x48, 0x8B, 0x4C, 0x24, 0x28]);
    emit_u64(&mut code, STUB_CLOSE_HANDLE);
    emit_call_rax(&mut code);

    // CreateFileA again
    emit_lea(&mut code, 0x48, 0x0D, file_off);
    emit_u64(&mut code, STUB_CREATE_FILE_A);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0x44, 0x24, 0x28]);

    // ReadFile(fh, crt_buf, len, &written, NULL)
    emit(&mut code, &[0x48, 0x89, 0xC1]);
    emit(&mut code, &[0x48, 0x8B, 0x54, 0x24, 0x38]);
    emit(
        &mut code,
        &[0x41, 0xB8, marker.len() as u8, 0x00, 0x00, 0x00],
    );
    emit_lea(&mut code, 0x4C, 0x0D, written_off);
    emit(
        &mut code,
        &[0x48, 0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x00],
    );
    emit_u64(&mut code, STUB_READ_FILE);
    emit_call_rax(&mut code);

    // CloseHandle(fh)
    emit(&mut code, &[0x48, 0x8B, 0x4C, 0x24, 0x28]);
    emit_u64(&mut code, STUB_CLOSE_HANDLE);
    emit_call_rax(&mut code);

    // GetStdHandle(-11); WriteFile(stdout, crt_buf, ...)
    emit(&mut code, &[0xB9, 0xF5, 0xFF, 0xFF, 0xFF]);
    emit_u64(&mut code, STUB_GET_STD_HANDLE);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0xC1]);
    emit(&mut code, &[0x48, 0x8B, 0x54, 0x24, 0x38]);
    emit(
        &mut code,
        &[0x41, 0xB8, marker.len() as u8, 0x00, 0x00, 0x00],
    );
    emit_lea(&mut code, 0x4C, 0x0D, written_off);
    emit(
        &mut code,
        &[0x48, 0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x00],
    );
    emit_u64(&mut code, STUB_WRITE_FILE);
    emit_call_rax(&mut code);

    // puts(crt_msg)
    emit_lea(&mut code, 0x48, 0x0D, crt_off);
    emit_u64(&mut code, STUB_PUTS);
    emit_call_rax(&mut code);

    // free(crt_buf)
    emit(&mut code, &[0x48, 0x8B, 0x4C, 0x24, 0x38]);
    emit_u64(&mut code, STUB_FREE);
    emit_call_rax(&mut code);

    // HeapFree(GetProcessHeap(), 0, heap_buf)
    emit_u64(&mut code, STUB_GET_PROCESS_HEAP);
    emit_call_rax(&mut code);
    emit(&mut code, &[0x48, 0x89, 0xC1]);
    emit(&mut code, &[0x31, 0xD2]);
    emit(&mut code, &[0x48, 0x8B, 0x44, 0x24, 0x30]);
    emit(&mut code, &[0x49, 0x89, 0xC0]); // mov r8, rax
    emit_u64(&mut code, STUB_HEAP_FREE);
    emit_call_rax(&mut code);

    // ExitProcess(0)
    emit(&mut code, &[0x31, 0xC9]);
    emit_u64(&mut code, STUB_EXIT_PROCESS);
    emit_call_rax(&mut code);

    assert!(
        code.len() <= code_capacity,
        "pe2 fixture code {} exceeds pad {}",
        code.len(),
        code_capacity
    );

    // NOP-pad so LEA targets (placed at code_capacity) stay correct.
    while code.len() < code_capacity {
        code.push(0x90);
    }

    pe[text..text + code.len()].copy_from_slice(&code);
    pe[text + marker_off..text + marker_off + marker.len()].copy_from_slice(marker);
    pe[text + crt_off..text + crt_off + crt_msg.len()].copy_from_slice(crt_msg);
    pe[text + file_off..text + file_off + filename.len()].copy_from_slice(filename);
    pe[text + written_off..text + written_off + 4].copy_from_slice(&0u32.to_le_bytes());

    pe
}
