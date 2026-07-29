//! nt-light-games-verify — StrawNT nt2 real lightweight Win demo evidence.
//!
//! Usage:
//!   nt-light-games-verify <out-json> [side-effects-dir] [fixtures-dir]
//!
//! Emits ≥2 real PE Win32 light-game demo binaries, launches each through the
//! native CPU loop (mode must be `real`), and records observable side effects.
//! Never treats mode=simulated as PASS.

use std::path::{Path, PathBuf};
use std::process::Command;

use strawwu_nt::{
    build_win32_light2d_game_demo_pe, build_win32_light3d_game_demo_pe, PeFile, PeSubsystem,
};
use strawwu_runtime::{execute_pe_with_side_effect_dir, AppProfile, RuntimeOrchestrator};

struct DemoSpec {
    id: &'static str,
    name: &'static str,
    dimension: &'static str,
    filename: &'static str,
    ok_marker: &'static str,
    closed_marker: &'static str,
    marker_file: &'static str,
    build: fn() -> Vec<u8>,
}

const DEMOS: &[DemoSpec] = &[
    DemoSpec {
        id: "light2d-win-demo",
        name: "Public Win32 2D light-game demo",
        dimension: "2d",
        filename: "nt2-light2d-demo.exe",
        ok_marker: "STRAWNT_LIGHT2D_OK",
        closed_marker: "STRAWNT_LIGHT2D_CLOSED",
        marker_file: "light2d-marker.txt",
        build: build_win32_light2d_game_demo_pe,
    },
    DemoSpec {
        id: "light3d-win-demo",
        name: "Public Win32 3D-present light-game demo",
        dimension: "3d",
        filename: "nt2-light3d-demo.exe",
        ok_marker: "STRAWNT_LIGHT3D_OK",
        closed_marker: "STRAWNT_LIGHT3D_CLOSED",
        marker_file: "light3d-marker.txt",
        build: build_win32_light3d_game_demo_pe,
    },
];

fn main() {
    let mut args = std::env::args().skip(1);
    let out_json = PathBuf::from(args.next().unwrap_or_else(|| {
        "tests/strawnt/output/nt2-light-games.json".into()
    }));
    let side_root = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("nt2-side-effects")
            .display()
            .to_string()
    }));
    let fixtures_dir = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .and_then(|p| p.parent())
            .unwrap_or_else(|| Path::new("."))
            .join("fixtures")
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

    let mut apps = Vec::new();
    let mut failures = Vec::new();

    for demo in DEMOS {
        match launch_demo(demo, &fixtures_dir, &side_root) {
            Ok(app) => {
                if app.get("mode").and_then(|v| v.as_str()) == Some("simulated") {
                    failures.push(format!("{} mode=simulated (forbidden)", demo.id));
                }
                if app.get("status").and_then(|v| v.as_str()) != Some("PASS") {
                    failures.push(format!("{} status != PASS", demo.id));
                }
                apps.push(app);
            }
            Err(e) => {
                failures.push(format!("{}: {e}", demo.id));
                apps.push(serde_json::json!({
                    "id": demo.id,
                    "name": demo.name,
                    "kind": "lightweight_public_win_demo",
                    "dimension": demo.dimension,
                    "mode": "simulated",
                    "backend": "native",
                    "status": "FAIL",
                    "error": e,
                    "disclaimer": "native launch failed; not full gameplay; no 3A or anti-cheat claim",
                }));
            }
        }
    }

    let all_real = apps.len() >= 2
        && apps.iter().all(|a| {
            a.get("mode").and_then(|v| v.as_str()) == Some("real")
                && a.get("status").and_then(|v| v.as_str()) == Some("PASS")
                && a.get("real_binary").and_then(|v| v.as_bool()) == Some(true)
        })
        && failures.is_empty();

    let status = if all_real { "PASS" } else { "FAIL" };

    let doc = serde_json::json!({
        "schema": "strawnt-nt2-light-games/v1",
        "stage": "nt2-real-light-games",
        "product": "StrawNT",
        "status": status,
        "version": version,
        "backend": "native",
        "execution_backend": "native",
        "real_binaries": all_real,
        "generated_at": generated_at,
        "component": "strawwu-nt+strawwu-runtime",
        "fixtures_dir": fixtures_dir.display().to_string(),
        "side_effects": {
            "dir": side_root.display().to_string(),
        },
        "apps": apps.clone(),
        "results": apps,
        "summary": {
            "total": DEMOS.len(),
            "pass": apps.iter().filter(|a| a.get("status").and_then(|v| v.as_str()) == Some("PASS")).count(),
            "real_mode": apps.iter().filter(|a| a.get("mode").and_then(|v| v.as_str()) == Some("real")).count(),
            "native_backend_only": true,
        },
        "failures": failures,
        "known_limitations": [
            "public Win32 light-game demo PE launch + present evidence only",
            "not full SuperTuxKart/OpenRA/3A gameplay coverage",
            "no anti-cheat ranked verification",
        ],
        "exclusions_honored": [
            "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
            "no Wine/Proton substrate; execution_backend=native",
            "no WinBox naming",
            "no full Windows compatibility claim",
            "no anti-cheat ranked pass claim",
            "no 3A completion claim",
            "mode=simulated never counts as PASS",
        ],
        "claims": {
            "real_binaries": all_real,
            "wine_proton_used": false,
            "native_pe_backend": true,
            "anti_cheat_claimed": false,
            "aaa_claimed": false,
            "full_windows_compat": false,
            "anticheat_ranked_pass": false,
            "simulated_ok": false,
        },
    });

    write_json(&out_json, &doc);
    println!(
        "nt-light-games-verify {} apps={} → {}",
        status,
        DEMOS.len(),
        out_json.display()
    );
    if status != "PASS" {
        for f in doc.get("failures").and_then(|v| v.as_array()).into_iter().flatten() {
            eprintln!("  FAIL: {}", f);
        }
        std::process::exit(1);
    }
}

fn launch_demo(
    demo: &DemoSpec,
    fixtures_dir: &Path,
    side_root: &Path,
) -> Result<serde_json::Value, String> {
    let pe = (demo.build)();
    let parsed = PeFile::parse(&pe).map_err(|e| format!("PE parse: {e:?}"))?;
    if !parsed.is_valid {
        return Err("PE parse invalid".into());
    }
    if parsed.subsystem != PeSubsystem::WindowsGui {
        return Err(format!("expected WindowsGui, got {:?}", parsed.subsystem));
    }

    let fixture_path = fixtures_dir.join(demo.filename);
    std::fs::write(&fixture_path, &pe).map_err(|e| format!("write fixture: {e}"))?;
    let sha256 = sha256_hex(&pe);
    let bytes = pe.len();

    let app_side = side_root.join(demo.id);
    let _ = std::fs::create_dir_all(&app_side);

    let mut orch = RuntimeOrchestrator::new();
    let mut profile = AppProfile::default_win32(demo.id);
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

    let gui = pe_exec
        .side_effects
        .as_ref()
        .and_then(|s| s.gui.clone())
        .ok_or_else(|| "missing GUI side effects".to_string())?;

    if gui.triangle_pixels <= 100 || gui.present_frames < 1 || gui.compositor_frames < 1 {
        return Err(format!(
            "insufficient present evidence pixels={} present={} compositor={}",
            gui.triangle_pixels, gui.present_frames, gui.compositor_frames
        ));
    }

    let stdout = pe_exec
        .side_effects
        .as_ref()
        .map(|s| s.stdout_utf8.clone())
        .unwrap_or_default();
    if !stdout.contains(demo.ok_marker) || !stdout.contains(demo.closed_marker) {
        return Err(format!("stdout markers missing: {stdout}"));
    }

    let marker_path = app_side.join(demo.marker_file);
    if !marker_path.is_file() {
        return Err(format!("missing marker file {}", marker_path.display()));
    }
    let marker_body =
        std::fs::read_to_string(&marker_path).map_err(|e| format!("read marker: {e}"))?;
    if !marker_body.contains(demo.ok_marker) {
        return Err(format!("marker body missing {}: {marker_body}", demo.ok_marker));
    }

    let shot = app_side.join("pe3-window.ppm");
    if !shot.is_file()
        || !std::fs::read(&shot)
            .map(|b| b.starts_with(b"P6"))
            .unwrap_or(false)
    {
        return Err(format!("missing/invalid screenshot {}", shot.display()));
    }

    let present = gui
        .present_path
        .clone()
        .filter(|p| Path::new(p).is_file())
        .or_else(|| {
            let p = app_side.join("nt-present.json");
            p.is_file().then(|| p.display().to_string())
        })
        .or_else(|| {
            let p = app_side.join("pe3-compositor.json");
            p.is_file().then(|| p.display().to_string())
        })
        .ok_or_else(|| "missing present/compositor observation".to_string())?;

    let log_path = app_side.join("launch.log");
    let log_body = format!(
        "strawnt native launch id={} path={} mode={} pid={} halt={:?}\nstdout:\n{stdout}\n",
        demo.id,
        fixture_path.display(),
        mode,
        pe_exec.pid,
        pe_exec.halt_reason
    );
    std::fs::write(&log_path, &log_body).map_err(|e| format!("write log: {e}"))?;

    Ok(serde_json::json!({
        "id": demo.id,
        "name": demo.name,
        "kind": "lightweight_public_win_demo",
        "dimension": demo.dimension,
        "scope": "launcher_present",
        "mode": mode,
        "backend": "native",
        "execution_backend": "native",
        "status": "PASS",
        "real_binary": true,
        "launch_verified": true,
        "binary": {
            "path": fixture_path.display().to_string(),
            "sha256": sha256,
            "bytes": bytes,
            "subsystem": "WindowsGui",
            "machine": "Amd64",
            "source": "StrawNT public Win32 light-game demo PE fixture",
        },
        "process": {
            "pid": pe_exec.pid,
            "session_id": pe_exec.session_id,
            "cpu_executed": pe_exec.cpu_executed,
            "halt_reason": pe_exec.halt_reason,
        },
        "side_effects": {
            "dir": app_side.display().to_string(),
            "stdout_marker": demo.ok_marker,
            "marker_file": marker_path.display().to_string(),
            "screenshot": shot.display().to_string(),
            "present_file": present,
            "log_file": log_path.display().to_string(),
            "triangle_pixels": gui.triangle_pixels,
            "present_frames": gui.present_frames,
            "compositor_frames": gui.compositor_frames,
            "title": gui.title,
        },
        "disclaimer": "launcher/present evidence only; not full gameplay; no 3A or anti-cheat claim",
        "notes": "真實 Win32 light-game demo PE 經 StrawNT native 啟動並留下 present／截圖／marker／log 副作用",
    }))
}

fn sha256_hex(data: &[u8]) -> String {
    // Prefer system sha256sum for deterministic evidence without extra crates.
    let tmp = std::env::temp_dir().join(format!("strawnt-nt2-{}.bin", std::process::id()));
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
