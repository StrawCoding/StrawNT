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

        Ok(Self {
            machine,
            subsystem,
            entry_point,
            image_base,
            sections,
            imports: Vec::new(),
            is_dll,
            is_valid: true,
        })
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
}
