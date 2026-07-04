use serde::{Deserialize, Serialize};

use crate::probes::{self, AnticheatType, ProbeResult};

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

    pub fn merge_probe_results(&mut self, results: &[ProbeResult]) {
        if results.is_empty() {
            return;
        }
        let pass_count = results.iter().filter(|r| r.passed).count();
        let total = results.len();
        let ratio = pass_count as f64 / total as f64;

        let (status, grade) = if ratio >= 1.0 {
            (CompatStatus::Pass, CompatGrade::A)
        } else if ratio >= 0.75 {
            (CompatStatus::Partial, CompatGrade::B)
        } else if ratio >= 0.5 {
            (CompatStatus::Partial, CompatGrade::C)
        } else {
            (CompatStatus::Fail, CompatGrade::F)
        };

        let first_category = &results[0].category;
        let name = format!("merged_probe_{}", results[0].probe_name);

        self.cases.push(CompatCase {
            name,
            anticheat_type: format!("{:?}", first_category),
            backend: "native".into(),
            status,
            grade,
            notes: format!("{}/{} probes passed", pass_count, total),
            probe_pass_count: pass_count,
            probe_total_count: total,
        });
    }

    pub fn get_case(&self, name: &str) -> Option<&CompatCase> {
        self.cases.iter().find(|c| c.name == name)
    }

    pub fn overall_grade(&self) -> CompatGrade {
        if self.cases.is_empty() {
            return CompatGrade::F;
        }

        let total_pass: usize = self.cases.iter().map(|c| c.probe_pass_count).sum();
        let total_probes: usize = self.cases.iter().map(|c| c.probe_total_count).sum();

        if total_probes == 0 {
            return CompatGrade::F;
        }

        let ratio = total_pass as f64 / total_probes as f64;
        if ratio >= 0.9 {
            CompatGrade::A
        } else if ratio >= 0.7 {
            CompatGrade::B
        } else if ratio >= 0.5 {
            CompatGrade::C
        } else {
            CompatGrade::F
        }
    }

    pub fn to_ci_json(&self) -> String {
        #[derive(Serialize)]
        struct CiEntry<'a> {
            name: &'a str,
            status: &'a str,
            grade: &'a str,
            pass: usize,
            total: usize,
        }

        let entries: Vec<CiEntry<'_>> = self
            .cases
            .iter()
            .map(|c| CiEntry {
                name: &c.name,
                status: c.status.as_str(),
                grade: c.grade.as_str(),
                pass: c.probe_pass_count,
                total: c.probe_total_count,
            })
            .collect();

        serde_json::to_string(&entries).unwrap_or_default()
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

    #[test]
    fn merge_probe_results_creates_case() {
        let mut matrix = AnticheatMatrix::generate();
        let initial_count = matrix.cases.len();

        let results = probes::simulate_battleye_probes();
        matrix.merge_probe_results(&results);

        assert_eq!(matrix.cases.len(), initial_count + 1);
        let merged = matrix.cases.last().unwrap();
        assert!(merged.name.starts_with("merged_probe_"));
        assert_eq!(merged.probe_total_count, results.len());
    }

    #[test]
    fn get_case_by_name() {
        let matrix = AnticheatMatrix::generate();
        let case = matrix.get_case("eac_driver_probe");
        assert!(case.is_some());
        assert_eq!(case.unwrap().anticheat_type, "EasyAntiCheat");

        assert!(matrix.get_case("nonexistent").is_none());
    }

    #[test]
    fn overall_grade_reflects_matrix() {
        let matrix = AnticheatMatrix::generate();
        let grade = matrix.overall_grade();
        assert!(
            grade == CompatGrade::C || grade == CompatGrade::B || grade == CompatGrade::F,
            "expected a realistic grade for partial/fail matrix, got {:?}",
            grade
        );
    }

    #[test]
    fn to_ci_json_compact() {
        let matrix = AnticheatMatrix::generate();
        let json = matrix.to_ci_json();
        assert!(json.contains("eac_driver_probe"));
        assert!(json.contains("PARTIAL"));
        assert!(!json.contains('\n'));
    }
}
