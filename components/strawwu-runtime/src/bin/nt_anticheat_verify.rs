//! nt-anticheat-verify — StrawNT nt4 honest anti-cheat matrix evidence.
//!
//! Usage:
//!   nt-anticheat-verify <out-json> [side-effects-dir] [fixtures-dir]
//!
//! Emits EAC / BattlEye / Vanguard / CustomAC probe cases with honest grades
//! A/B/C/F (anti-cheat capped ≤B; Vanguard = F). Runs real StrawNT probe PE
//! binaries for EAC/BE/CustomAC via native CPU (mode=real + host side effects).
//! Vanguard remains probe-matrix + grade F (no fake kernel/TPM pass).
//!
//! Top-level status is always PARTIAL for honesty — never claims ranked play
//! or official AC signature pass. Never uses Wine/Proton.

use std::path::{Path, PathBuf};
use std::process::Command;

use strawwu_anticheat::substantive::generate_substantive_report_for_stage;
use strawwu_nt::{
    build_win32_battleye_probe_pe, build_win32_custom_ac_probe_pe, build_win32_eac_probe_pe, PeFile,
    PeSubsystem,
};
use strawwu_runtime::{execute_pe_with_side_effect_dir, AppProfile, RuntimeOrchestrator};

const STAGE: &str = "nt4-anticheat-honest";

struct PeProbeSpec {
    case_name: &'static str,
    anticheat_type: &'static str,
    filename: &'static str,
    ok_marker: &'static str,
    marker_file: &'static str,
    build: fn() -> Vec<u8>,
}

const PE_PROBES: &[PeProbeSpec] = &[
    PeProbeSpec {
        case_name: "eac_driver_probe",
        anticheat_type: "EasyAntiCheat",
        filename: "nt4-eac-probe.exe",
        ok_marker: "STRAWNT_EAC_PROBE_OK",
        marker_file: "eac-probe-marker.txt",
        build: build_win32_eac_probe_pe,
    },
    PeProbeSpec {
        case_name: "battleye_init",
        anticheat_type: "BattlEye",
        filename: "nt4-battleye-probe.exe",
        ok_marker: "STRAWNT_BE_PROBE_OK",
        marker_file: "be-probe-marker.txt",
        build: build_win32_battleye_probe_pe,
    },
    PeProbeSpec {
        case_name: "custom_ac_window_process",
        anticheat_type: "CustomAC",
        filename: "nt4-custom-ac-probe.exe",
        ok_marker: "STRAWNT_CUSTOM_AC_PROBE_OK",
        marker_file: "custom-ac-probe-marker.txt",
        build: build_win32_custom_ac_probe_pe,
    },
];

fn main() {
    let mut args = std::env::args().skip(1);
    let out_json = PathBuf::from(args.next().unwrap_or_else(|| {
        "tests/strawnt/output/nt4-anticheat.json".into()
    }));
    let side_root = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("nt4-side-effects")
            .display()
            .to_string()
    }));
    let fixtures_dir = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .and_then(|p| p.parent())
            .unwrap_or_else(|| Path::new("."))
            .join("fixtures")
            .join("anticheat")
            .display()
            .to_string()
    }));

    let version = std::fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join("VERSION"),
    )
    .ok()
    .map(|s| s.trim().to_string())
    .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());

    let generated_at = utc_now();
    let _ = std::fs::remove_dir_all(&side_root);
    let _ = std::fs::create_dir_all(&side_root);
    let _ = std::fs::create_dir_all(&fixtures_dir);

    let report = generate_substantive_report_for_stage(&version, STAGE);

    let mut pe_by_case = std::collections::HashMap::new();
    let mut pe_failures = Vec::new();
    for spec in PE_PROBES {
        match launch_pe_probe(spec, &fixtures_dir, &side_root) {
            Ok(row) => {
                pe_by_case.insert(spec.case_name.to_string(), row);
            }
            Err(e) => {
                pe_failures.push(format!("{}: {e}", spec.case_name));
                pe_by_case.insert(
                    spec.case_name.to_string(),
                    serde_json::json!({
                        "real_binary": false,
                        "mode": "simulated",
                        "error": e,
                    }),
                );
            }
        }
    }

    let mut cases = Vec::new();
    for c in &report.cases {
        let mut status = c.status.clone();
        // Harden honesty: never elevate anticheat case to PASS / grade A.
        if status == "PASS" {
            status = "PARTIAL".into();
        }
        let grade = if c.name == "vanguard_tpm_probe" {
            "F".to_string()
        } else if c.grade == "A" {
            "B".to_string()
        } else {
            c.grade.clone()
        };

        let pe = pe_by_case.get(&c.name).cloned();
        let pe_real = pe
            .as_ref()
            .and_then(|p| p.get("mode"))
            .and_then(|v| v.as_str())
            == Some("real");
        let pe_mode = pe
            .as_ref()
            .and_then(|p| p.get("mode"))
            .and_then(|v| v.as_str())
            .unwrap_or("n/a");

        let evidence = &c.evidence;
        let probe_pass = evidence.probe_pass;
        let probe_total = evidence.probe_total;
        let ratio = if probe_total > 0 {
            (probe_pass as f64) / (probe_total as f64)
        } else {
            0.0
        };

        let mut notes = c.notes.clone();
        if c.name == "vanguard_tpm_probe" {
            notes.push_str(
                "; no vendor Vanguard PE claimed — kernel/TPM remain grade F by policy",
            );
        } else if pe_real {
            notes.push_str("; StrawNT surface-probe PE ran mode=real with host side effects");
        }

        cases.push(serde_json::json!({
            "name": c.name,
            "anticheat_type": c.anticheat_type,
            "backend": c.backend,
            "execution_backend": if c.backend == "microvm" { "microvm" } else { "native" },
            "status": status,
            "grade": grade,
            "substantive_verified": c.substantive_verified,
            "probe_pass": probe_pass,
            "probe_total": probe_total,
            "probe_ratio": (ratio * 1000.0).round() / 1000.0,
            "bridge_policy_side_effect": evidence.bridge_policy_side_effect,
            "real_probe_pe": pe_real,
            "pe_mode": pe_mode,
            "pe": pe,
            "notes": notes,
            "disclaimer": evidence.honest_disclaimer,
            "probes": evidence.probes.iter().map(|p| serde_json::json!({
                "probe_name": p.probe_name,
                "category": p.category,
                "passed": p.passed,
                "response": p.response,
            })).collect::<Vec<_>>(),
        }));
    }

    let real_pe_count = cases
        .iter()
        .filter(|c| c.get("real_probe_pe").and_then(|v| v.as_bool()) == Some(true))
        .count();
    let grades: Vec<String> = {
        let mut g: Vec<String> = cases
            .iter()
            .filter_map(|c| c.get("grade").and_then(|v| v.as_str()).map(|s| s.to_string()))
            .collect();
        g.sort();
        g.dedup();
        g
    };

    // Honest: anti-cheat matrix never claims top-level PASS (ranked / official).
    let status = if cases.is_empty() {
        "FAIL"
    } else if pe_failures.len() == PE_PROBES.len() && real_pe_count == 0 {
        // Matrix probes still ran; keep PARTIAL if substantive cases exist, else FAIL.
        "PARTIAL"
    } else {
        "PARTIAL"
    };

    let failures = pe_failures;
    let doc = serde_json::json!({
        "schema": "strawnt-nt4-anticheat/v1",
        "stage": STAGE,
        "product": "StrawNT",
        "status": status,
        "version": version,
        "backend": "native",
        "execution_backend": "native",
        "real_binaries": real_pe_count >= 1,
        "generated_at": generated_at,
        "component": "strawwu-anticheat+strawwu-nt+strawwu-runtime",
        "source": {
            "crate": "strawwu-anticheat",
            "verify_bin": "nt-anticheat-verify",
            "raw_schema": report.schema,
            "verification_stage": STAGE,
        },
        "fixtures_dir": fixtures_dir.display().to_string(),
        "side_effects": {
            "dir": side_root.display().to_string(),
        },
        "claims": {
            "real_binaries": real_pe_count >= 1,
            "wine_proton_used": false,
            "path_role": "legacy_native",
            "native_pe_backend": true,
            "anti_cheat_claimed": false,
            "ranked_pass_claimed": false,
            "anticheat_ranked_pass": false,
            "aaa_claimed": false,
            "full_windows_compat": false,
            "simulated_ok": false,
            "official_ac_signature_pass": false,
        },
        "cases": cases.clone(),
        "results": cases,
        "summary": {
            "total_cases": report.cases.len(),
            "partial_or_fail_only": true,
            "grades_present": grades,
            "bridge_policy_side_effects": report.cases.iter().filter(|c| c.evidence.bridge_policy_side_effect).count(),
            "real_probe_pe_count": real_pe_count,
            "overall_from_engine": report.overall,
            "vanguard_grade_f": true,
            "hub_a_forbidden": true,
        },
        "failures": failures,
        "known_limitations": [
            "StrawNT surface-probe PEs + ProbeEngine + bridge PolicySet — NOT vendor EAC/BattlEye/Vanguard binaries",
            "goal is run-without-crash + honest A/B/C/F grades (anti-cheat cap ≤B)",
            "never claims ranked play or official AC signature pass",
            "Vanguard kernel/TPM remain grade F by policy",
            "top-level PASS forbidden for anticheat honesty matrix",
        ],
        "exclusions_honored": [
            "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
            "legacy_native research path; product default wine/proton-ge (NTW0); powered by Wine",
            "no WinBox naming",
            "no full Windows compatibility claim",
            "no anti-cheat ranked pass claim",
            "no official AC signature pass claim",
            "no 3A completion claim",
            "mode=simulated never elevated to top-level PASS",
        ],
    });

    write_json(&out_json, &doc);
    println!(
        "nt-anticheat-verify {} cases={} real_pe={} → {}",
        status,
        report.cases.len(),
        real_pe_count,
        out_json.display()
    );

    if status == "FAIL" || cases.is_empty() {
        for f in &doc["failures"].as_array().cloned().unwrap_or_default() {
            eprintln!("  FAIL: {}", f);
        }
        std::process::exit(1);
    }
    // Require at least one real PE probe for YouWan honesty (PARTIAL allowed).
    if real_pe_count < 1 {
        eprintln!("  FAIL: need ≥1 real probe PE with mode=real side effects");
        for f in &doc["failures"].as_array().cloned().unwrap_or_default() {
            eprintln!("  detail: {}", f);
        }
        let mut fail_doc = doc;
        fail_doc["status"] = serde_json::json!("FAIL");
        fail_doc["failures"] = serde_json::json!(["need ≥1 real probe PE with mode=real side effects"]);
        write_json(&out_json, &fail_doc);
        std::process::exit(1);
    }
}

fn launch_pe_probe(
    spec: &PeProbeSpec,
    fixtures_dir: &Path,
    side_root: &Path,
) -> Result<serde_json::Value, String> {
    let pe = (spec.build)();
    let parsed = PeFile::parse(&pe).map_err(|e| format!("PE parse: {e:?}"))?;
    if !parsed.is_valid {
        return Err("PE parse invalid".into());
    }
    if parsed.subsystem != PeSubsystem::WindowsCui {
        return Err(format!("expected WindowsCui, got {:?}", parsed.subsystem));
    }

    let fixture_path = fixtures_dir.join(spec.filename);
    std::fs::write(&fixture_path, &pe).map_err(|e| format!("write fixture: {e}"))?;
    let sha256 = sha256_hex(&pe);
    let bytes = pe.len();

    let app_side = side_root.join(spec.case_name);
    let _ = std::fs::create_dir_all(&app_side);

    let mut orch = RuntimeOrchestrator::new();
    let mut profile = AppProfile::default_win32(spec.case_name);
    profile.execution_backend = "native".into();

    let pe_exec = execute_pe_with_side_effect_dir(
        &mut orch,
        &profile,
        &pe,
        Some(app_side.clone()),
    );

    let mode = pe_exec.mode.clone();
    if mode == "simulated" {
        return Err(format!(
            "mode=simulated (cpu={} err={:?})",
            pe_exec.cpu_executed, pe_exec.error
        ));
    }
    if pe_exec.error.is_some() || !pe_exec.cpu_executed {
        return Err(format!(
            "native exec incomplete cpu={} err={:?}",
            pe_exec.cpu_executed, pe_exec.error
        ));
    }

    let stdout = pe_exec
        .side_effects
        .as_ref()
        .map(|s| s.stdout_utf8.clone())
        .unwrap_or_default();
    if !stdout.contains(spec.ok_marker) {
        return Err(format!("stdout missing {}: {stdout}", spec.ok_marker));
    }

    let marker_path = app_side.join(spec.marker_file);
    if !marker_path.is_file() {
        return Err(format!("missing marker file {}", marker_path.display()));
    }
    let marker_body =
        std::fs::read_to_string(&marker_path).map_err(|e| format!("read marker: {e}"))?;
    if !marker_body.contains(spec.ok_marker) {
        return Err(format!(
            "marker body missing {}: {marker_body}",
            spec.ok_marker
        ));
    }

    let log_path = app_side.join("launch.log");
    let log_body = format!(
        "strawnt anticheat probe id={} type={} path={} mode={} pid={} halt={:?}\nstdout:\n{stdout}\n",
        spec.case_name,
        spec.anticheat_type,
        fixture_path.display(),
        mode,
        pe_exec.pid,
        pe_exec.halt_reason
    );
    std::fs::write(&log_path, &log_body).map_err(|e| format!("write log: {e}"))?;

    let host_files = pe_exec
        .side_effects
        .as_ref()
        .map(|s| s.host_files_written.clone())
        .unwrap_or_default();

    Ok(serde_json::json!({
        "path": fixture_path.display().to_string(),
        "sha256": sha256,
        "bytes": bytes,
        "subsystem": "WindowsCui",
        "machine": "Amd64",
        "source": "StrawNT anticheat surface-probe PE fixture (not vendor AC)",
        "mode": mode,
        "real_binary": true,
        "pid": pe_exec.pid,
        "session_id": pe_exec.session_id,
        "cpu_executed": pe_exec.cpu_executed,
        "halt_reason": pe_exec.halt_reason,
        "side_effects": {
            "dir": app_side.display().to_string(),
            "marker_file": marker_path.display().to_string(),
            "log_file": log_path.display().to_string(),
            "stdout_marker": spec.ok_marker,
            "host_files": host_files,
        },
        "disclaimer": "surface probe only — NOT vendor EAC/BE/Vanguard; no ranked/signature claim",
    }))
}

fn sha256_hex(data: &[u8]) -> String {
    let tmp = std::env::temp_dir().join(format!("strawnt-nt4-{}.bin", std::process::id()));
    if std::fs::write(&tmp, data).is_ok() {
        if let Ok(out) = Command::new("sha256sum").arg(&tmp).output() {
            let _ = std::fs::remove_file(&tmp);
            if out.status.success() {
                let s = String::from_utf8_lossy(&out.stdout);
                if let Some(hash) = s.split_whitespace().next() {
                    return hash.to_string();
                }
            }
        }
        let _ = std::fs::remove_file(&tmp);
    }
    format!("len:{}", data.len())
}

fn write_json(path: &PathBuf, doc: &serde_json::Value) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let body = serde_json::to_string_pretty(doc).expect("serialize");
    std::fs::write(path, body + "\n").expect("write json");
}

fn utc_now() -> String {
    if let Ok(out) = Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output()
    {
        if out.status.success() {
            return String::from_utf8_lossy(&out.stdout).trim().to_string();
        }
    }
    "1970-01-01T00:00:00Z".into()
}
