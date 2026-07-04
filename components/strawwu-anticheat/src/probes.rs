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

pub fn simulate_window_enumeration_probes() -> Vec<ProbeResult> {
    vec![
        ProbeResult {
            category: ProbeCategory::WindowEnumeration,
            probe_name: "hidden_window_check".into(),
            passed: true,
            response: "no suspicious hidden windows detected in enum".into(),
        },
        ProbeResult {
            category: ProbeCategory::WindowEnumeration,
            probe_name: "overlay_window_check".into(),
            passed: true,
            response: "overlay windows filtered from enumeration".into(),
        },
        ProbeResult {
            category: ProbeCategory::WindowEnumeration,
            probe_name: "tool_window_visibility".into(),
            passed: false,
            response: "debug tool window visible — PARTIAL".into(),
        },
    ]
}

pub fn simulate_process_scan_probes() -> Vec<ProbeResult> {
    vec![
        ProbeResult {
            category: ProbeCategory::ProcessScan,
            probe_name: "process_list_filter".into(),
            passed: true,
            response: "host-side processes hidden from guest enumeration".into(),
        },
        ProbeResult {
            category: ProbeCategory::ProcessScan,
            probe_name: "module_list_filter".into(),
            passed: true,
            response: "injected modules not visible in LDR list".into(),
        },
        ProbeResult {
            category: ProbeCategory::ProcessScan,
            probe_name: "thread_enumeration".into(),
            passed: true,
            response: "bridge threads excluded from NtQuerySystemInformation".into(),
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

use std::collections::HashMap;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProbeEngine {
    run_history: HashMap<String, Vec<ProbeResult>>,
    run_count: u64,
}

impl ProbeEngine {
    pub fn new() -> Self {
        Self {
            run_history: HashMap::new(),
            run_count: 0,
        }
    }

    pub fn run_probe_suite(&mut self, ac_type: AnticheatType) -> Vec<ProbeResult> {
        let mut results = match ac_type {
            AnticheatType::EasyAntiCheat => simulate_eac_probes(),
            AnticheatType::BattlEye => simulate_battleye_probes(),
            AnticheatType::Vanguard => simulate_vanguard_probes(),
            AnticheatType::CustomAc | AnticheatType::None => {
                simulate_process_scan_probes()
            }
        };

        results.extend(simulate_window_enumeration_probes());
        results.extend(simulate_process_scan_probes());

        self.run_count += 1;
        let key = ac_type.as_str().to_string();
        self.run_history
            .entry(key)
            .or_default()
            .extend(results.clone());

        results
    }

    pub fn probe_pass_rate(&self, ac_type: AnticheatType) -> f64 {
        let key = ac_type.as_str();
        match self.run_history.get(key) {
            Some(results) if !results.is_empty() => {
                let passed = results.iter().filter(|r| r.passed).count();
                passed as f64 / results.len() as f64
            }
            _ => 0.0,
        }
    }

    pub fn total_runs(&self) -> u64 {
        self.run_count
    }

    pub fn results_for(&self, ac_type: AnticheatType) -> &[ProbeResult] {
        match self.run_history.get(ac_type.as_str()) {
            Some(v) => v,
            None => &[],
        }
    }
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

    #[test]
    fn window_enumeration_probes_run() {
        let results = simulate_window_enumeration_probes();
        assert_eq!(results.len(), 3);
        assert!(results.iter().any(|r| r.category == ProbeCategory::WindowEnumeration));
        assert!(results.iter().any(|r| !r.passed));
    }

    #[test]
    fn process_scan_probes_all_pass() {
        let results = simulate_process_scan_probes();
        assert_eq!(results.len(), 3);
        assert!(results.iter().all(|r| r.passed));
    }

    #[test]
    fn probe_engine_run_suite_eac() {
        let mut engine = ProbeEngine::new();
        let results = engine.run_probe_suite(AnticheatType::EasyAntiCheat);
        assert!(!results.is_empty());
        assert_eq!(engine.total_runs(), 1);

        let stored = engine.results_for(AnticheatType::EasyAntiCheat);
        assert_eq!(stored.len(), results.len());
    }

    #[test]
    fn probe_engine_pass_rate() {
        let mut engine = ProbeEngine::new();
        engine.run_probe_suite(AnticheatType::BattlEye);

        let rate = engine.probe_pass_rate(AnticheatType::BattlEye);
        assert!(rate > 0.0 && rate <= 1.0);

        assert_eq!(engine.probe_pass_rate(AnticheatType::Vanguard), 0.0);
    }

    #[test]
    fn probe_engine_multiple_runs_accumulate() {
        let mut engine = ProbeEngine::new();
        engine.run_probe_suite(AnticheatType::EasyAntiCheat);
        let count1 = engine.results_for(AnticheatType::EasyAntiCheat).len();

        engine.run_probe_suite(AnticheatType::EasyAntiCheat);
        let count2 = engine.results_for(AnticheatType::EasyAntiCheat).len();

        assert_eq!(count2, count1 * 2);
        assert_eq!(engine.total_runs(), 2);
    }
}
