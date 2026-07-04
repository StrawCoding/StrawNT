use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AnticheatType {
    EasyAntiCheat,
    BattlEye,
    Vanguard,
    CustomAc,
    None,
}

impl AnticheatType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::EasyAntiCheat => "EasyAntiCheat",
            Self::BattlEye => "BattlEye",
            Self::Vanguard => "Vanguard",
            Self::CustomAc => "CustomAC",
            Self::None => "None",
        }
    }

    pub fn recommended_backend(&self) -> &'static str {
        match self {
            Self::EasyAntiCheat => "native",
            Self::BattlEye => "native",
            Self::Vanguard => "microvm",
            Self::CustomAc => "native",
            Self::None => "native",
        }
    }

    pub fn recommended_syscall_profile(&self) -> &'static str {
        match self {
            Self::EasyAntiCheat | Self::BattlEye => "anticheat",
            Self::Vanguard => "anticheat",
            Self::CustomAc => "game",
            Self::None => "daily",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ProbeCategory {
    DriverSignature,
    KernelCallback,
    DllIntegrity,
    DebuggerDetection,
    TpmCheck,
    KernelModuleScan,
    WindowEnumeration,
    ProcessScan,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProbeResult {
    pub category: ProbeCategory,
    pub probe_name: String,
    pub passed: bool,
    pub response: String,
}

pub fn simulate_eac_probes() -> Vec<ProbeResult> {
    vec![
        ProbeResult {
            category: ProbeCategory::DriverSignature,
            probe_name: "eac_driver_loaded".into(),
            passed: true,
            response: "stub driver present via strawwu_ipc".into(),
        },
        ProbeResult {
            category: ProbeCategory::KernelCallback,
            probe_name: "eac_kernel_callback".into(),
            passed: true,
            response: "callback stub registered".into(),
        },
        ProbeResult {
            category: ProbeCategory::DllIntegrity,
            probe_name: "eac_dll_integrity".into(),
            passed: false,
            response: "DLL hash mismatch expected — PARTIAL".into(),
        },
    ]
}

pub fn simulate_battleye_probes() -> Vec<ProbeResult> {
    vec![
        ProbeResult {
            category: ProbeCategory::KernelModuleScan,
            probe_name: "be_kernel_scan".into(),
            passed: true,
            response: "scan intercepted by bridge".into(),
        },
        ProbeResult {
            category: ProbeCategory::DllIntegrity,
            probe_name: "be_dll_check".into(),
            passed: true,
            response: "DLL integrity stub pass".into(),
        },
        ProbeResult {
            category: ProbeCategory::DebuggerDetection,
            probe_name: "be_debugger_check".into(),
            passed: true,
            response: "NtQueryInformationProcess returns no debugger".into(),
        },
    ]
}

pub fn simulate_vanguard_probes() -> Vec<ProbeResult> {
    vec![
        ProbeResult {
            category: ProbeCategory::TpmCheck,
            probe_name: "vanguard_tpm_probe".into(),
            passed: false,
            response: "TPM stub — PARTIAL, no real TPM attestation".into(),
        },
        ProbeResult {
            category: ProbeCategory::DriverSignature,
            probe_name: "vanguard_kernel_driver".into(),
            passed: false,
            response: "kernel-mode driver not loaded — policy deny".into(),
        },
        ProbeResult {
            category: ProbeCategory::ProcessScan,
            probe_name: "vanguard_process_scan".into(),
            passed: true,
            response: "process list filtered".into(),
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eac_probes_run_without_crash() {
        let results = simulate_eac_probes();
        assert!(!results.is_empty());
        assert!(results.iter().any(|r| r.probe_name == "eac_driver_loaded"));
    }

    #[test]
    fn battleye_probes_run_without_crash() {
        let results = simulate_battleye_probes();
        assert!(!results.is_empty());
        assert!(results.iter().all(|r| r.passed));
    }

    #[test]
    fn vanguard_probes_partial() {
        let results = simulate_vanguard_probes();
        assert!(!results.is_empty());
        let tpm = results.iter().find(|r| r.probe_name == "vanguard_tpm_probe").unwrap();
        assert!(!tpm.passed);
    }

    #[test]
    fn anticheat_recommended_backends() {
        assert_eq!(AnticheatType::EasyAntiCheat.recommended_backend(), "native");
        assert_eq!(AnticheatType::Vanguard.recommended_backend(), "microvm");
    }

    #[test]
    fn anticheat_type_str() {
        assert_eq!(AnticheatType::EasyAntiCheat.as_str(), "EasyAntiCheat");
        assert_eq!(AnticheatType::BattlEye.as_str(), "BattlEye");
    }
}
