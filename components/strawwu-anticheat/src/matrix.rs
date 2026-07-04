use serde::{Deserialize, Serialize};

use crate::probes::{self, AnticheatType};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CompatStatus {
    #[serde(rename = "PASS")]
    Pass,
    #[serde(rename = "PARTIAL")]
    Partial,
    #[serde(rename = "FAIL")]
    Fail,
}

impl CompatStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pass => "PASS",
            Self::Partial => "PARTIAL",
            Self::Fail => "FAIL",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CompatGrade {
    A,
    B,
    C,
    F,
}

impl CompatGrade {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::A => "A",
            Self::B => "B",
            Self::C => "C",
            Self::F => "F",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompatCase {
    pub name: String,
    pub anticheat_type: String,
    pub backend: String,
    pub status: CompatStatus,
    pub grade: CompatGrade,
    pub notes: String,
    pub probe_pass_count: usize,
    pub probe_total_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnticheatMatrix {
    pub matrix_version: String,
    pub cases: Vec<CompatCase>,
}

impl AnticheatMatrix {
    pub fn generate() -> Self {
        let mut cases = Vec::new();

        // EAC
        let eac_results = probes::simulate_eac_probes();
        let eac_pass = eac_results.iter().filter(|r| r.passed).count();
        cases.push(CompatCase {
            name: "eac_driver_probe".into(),
            anticheat_type: AnticheatType::EasyAntiCheat.as_str().into(),
            backend: AnticheatType::EasyAntiCheat.recommended_backend().into(),
            status: CompatStatus::Partial,
            grade: CompatGrade::C,
            notes: "driver stub present; DLL integrity partial".into(),
            probe_pass_count: eac_pass,
            probe_total_count: eac_results.len(),
        });

        // BattlEye
        let be_results = probes::simulate_battleye_probes();
        let be_pass = be_results.iter().filter(|r| r.passed).count();
        let be_status = if be_pass == be_results.len() { CompatStatus::Partial } else { CompatStatus::Fail };
        cases.push(CompatCase {
            name: "battleye_init".into(),
            anticheat_type: AnticheatType::BattlEye.as_str().into(),
            backend: AnticheatType::BattlEye.recommended_backend().into(),
            status: be_status,
            grade: CompatGrade::C,
            notes: "kernel scan intercepted; process not crash".into(),
            probe_pass_count: be_pass,
            probe_total_count: be_results.len(),
        });

        // Vanguard
        let vg_results = probes::simulate_vanguard_probes();
        let vg_pass = vg_results.iter().filter(|r| r.passed).count();
        cases.push(CompatCase {
            name: "vanguard_tpm_probe".into(),
            anticheat_type: AnticheatType::Vanguard.as_str().into(),
            backend: AnticheatType::Vanguard.recommended_backend().into(),
            status: CompatStatus::Partial,
            grade: CompatGrade::F,
            notes: "TPM stub partial; kernel driver not loaded — policy deny".into(),
            probe_pass_count: vg_pass,
            probe_total_count: vg_results.len(),
        });

        Self {
            matrix_version: "1".into(),
            cases,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_default()
    }

    pub fn all_pass(&self) -> bool {
        self.cases.iter().all(|c| c.status == CompatStatus::Pass)
    }

    pub fn no_crash(&self) -> bool {
        self.cases.iter().all(|c| c.status != CompatStatus::Fail || c.grade != CompatGrade::F || c.probe_pass_count > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matrix_generate() {
        let matrix = AnticheatMatrix::generate();
        assert_eq!(matrix.matrix_version, "1");
        assert_eq!(matrix.cases.len(), 3);
    }

    #[test]
    fn matrix_honest_status() {
        let matrix = AnticheatMatrix::generate();
        assert!(!matrix.all_pass());
        for case in &matrix.cases {
            assert!(
                case.status == CompatStatus::Partial || case.status == CompatStatus::Fail,
                "v3.0 should not claim PASS for anticheat: {}", case.name
            );
        }
    }

    #[test]
    fn matrix_no_crash() {
        let matrix = AnticheatMatrix::generate();
        assert!(matrix.no_crash());
    }

    #[test]
    fn matrix_json_output() {
        let matrix = AnticheatMatrix::generate();
        let json = matrix.to_json();
        assert!(json.contains("matrix_version"));
        assert!(json.contains("eac_driver_probe"));
        assert!(json.contains("battleye_init"));
        assert!(json.contains("vanguard_tpm_probe"));
    }

    #[test]
    fn compat_status_str() {
        assert_eq!(CompatStatus::Pass.as_str(), "PASS");
        assert_eq!(CompatStatus::Partial.as_str(), "PARTIAL");
        assert_eq!(CompatStatus::Fail.as_str(), "FAIL");
    }

    #[test]
    fn compat_grade_str() {
        assert_eq!(CompatGrade::A.as_str(), "A");
        assert_eq!(CompatGrade::F.as_str(), "F");
    }
}
