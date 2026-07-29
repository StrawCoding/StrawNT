//! nt-graphics-verify — StrawNT nt1 native PE triangle/present evidence.
//!
//! Usage:
//!   nt-graphics-verify <out-json> [side-effects-dir] [width] [height]
//!
//! Runs a real Win32 GUI PE through the native CPU loop (mode must be `real`),
//! producing observable triangle PPM + present JSON side effects. Also runs the
//! DXGI/D3D11→VK + wgl graphics pipeline into the same side-effect directory
//! for present/triangle path coverage. Never treats mode=simulated as PASS.

use std::path::{Path, PathBuf};
use std::process::Command;

use strawwu_nt::pe::build_win32_gui_mvp_pe;
use strawwu_runtime::{
    execute_pe_with_side_effect_dir, run_portable_graphics_smoke, AppProfile, RuntimeOrchestrator,
};

fn main() {
    let mut args = std::env::args().skip(1);
    let out_json = PathBuf::from(args.next().unwrap_or_else(|| {
        "tests/strawnt/output/nt1-graphics.json".into()
    }));
    let side_dir = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("nt1-side-effects")
            .display()
            .to_string()
    }));
    let width: u32 = args
        .next()
        .and_then(|s| s.parse().ok())
        .unwrap_or(640);
    let height: u32 = args
        .next()
        .and_then(|s| s.parse().ok())
        .unwrap_or(480);

    let version = std::fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join("VERSION"),
    )
    .ok()
    .map(|s| s.trim().to_string())
    .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());

    let generated_at = utc_now();
    let _ = std::fs::remove_dir_all(&side_dir);
    let _ = std::fs::create_dir_all(&side_dir);

    let pe = build_win32_gui_mvp_pe();
    let mut orch = RuntimeOrchestrator::new();
    let mut profile = AppProfile::default_win32("strawnt-nt1-graphics");
    profile.execution_backend = "native".into();

    let pe_exec = execute_pe_with_side_effect_dir(
        &mut orch,
        &profile,
        &pe,
        Some(side_dir.clone()),
    );

    let gx_dir = side_dir.join("gx-pipeline");
    let _ = std::fs::create_dir_all(&gx_dir);
    let gx = run_portable_graphics_smoke(&gx_dir, width, height);

    let pe_mode = pe_exec.mode.clone();
    let pe_ok = pe_mode != "simulated"
        && pe_exec.cpu_executed
        && pe_exec.error.is_none()
        && pe_exec
            .side_effects
            .as_ref()
            .and_then(|s| s.gui.as_ref())
            .map(|g| g.triangle_pixels > 100 && g.present_frames >= 1 && g.compositor_frames >= 1)
            .unwrap_or(false);

    let gx_ok = match &gx {
        Ok(r) => r.status == "PASS" && r.triangle_pixels > 100 && r.present_frames >= 1,
        Err(_) => false,
    };

    let triangle_file = side_dir.join("nt-triangle.ppm");
    let present_file = side_dir.join("nt-present.json");
    let pe_gui = pe_exec
        .side_effects
        .as_ref()
        .and_then(|s| s.gui.clone());

    let side_triangle = if triangle_file.is_file() {
        triangle_file.display().to_string()
    } else {
        pe_gui
            .as_ref()
            .and_then(|g| g.triangle_path.clone())
            .unwrap_or_default()
    };
    let side_present = if present_file.is_file() {
        present_file.display().to_string()
    } else {
        pe_gui
            .as_ref()
            .and_then(|g| g.present_path.clone())
            .unwrap_or_default()
    };

    let triangle_bytes_ok = Path::new(&side_triangle)
        .metadata()
        .map(|m| m.len() > 0)
        .unwrap_or(false)
        && std::fs::read(&side_triangle)
            .map(|b| b.starts_with(b"P6"))
            .unwrap_or(false);
    let present_bytes_ok = Path::new(&side_present)
        .metadata()
        .map(|m| m.len() > 0)
        .unwrap_or(false);

    // Top-level PASS requires real PE mode + triangle/present side effects.
    // Graphics pipeline evidence is required alongside (real pixels, not stub-only).
    let status = if pe_ok && gx_ok && triangle_bytes_ok && present_bytes_ok {
        "PASS"
    } else {
        "FAIL"
    };

    let mut failures = Vec::new();
    if pe_mode == "simulated" {
        failures.push("pe_mode=simulated (forbidden for nt1 PASS)".into());
    }
    if !pe_ok {
        failures.push(format!(
            "native PE graphics path incomplete (mode={pe_mode}, cpu={}, err={:?})",
            pe_exec.cpu_executed, pe_exec.error
        ));
    }
    if !gx_ok {
        failures.push(match &gx {
            Ok(r) => format!("graphics pipeline status={} pixels={}", r.status, r.triangle_pixels),
            Err(e) => format!("graphics pipeline error: {e}"),
        });
    }
    if !triangle_bytes_ok {
        failures.push(format!("triangle side-effect missing/empty: {side_triangle}"));
    }
    if !present_bytes_ok {
        failures.push(format!("present side-effect missing/empty: {side_present}"));
    }

    let gx_json = gx.as_ref().ok().map(|r| {
        serde_json::json!({
            "status": r.status,
            "triangles_drawn": r.triangles_drawn,
            "triangle_pixels": r.triangle_pixels,
            "vk_frames": r.vk_frames,
            "present_frames": r.present_frames,
            "wgl_frames": r.wgl_frames,
            "dxgi_frames": r.dxgi_frames,
            "screenshot": r.screenshot_path,
            "present_obs": r.present_obs_path,
            "gaps": r.gaps,
        })
    });

    let doc = serde_json::json!({
        "schema": "strawnt-nt1-graphics/v1",
        "stage": "nt1-real-graphics",
        "product": "StrawNT",
        "status": status,
        "version": version,
        "mode": pe_mode,
        "backend": "native",
        "execution_backend": "native",
        "generated_at": generated_at,
        "component": "strawwu-nt+strawwu-graphics",
        "pe": {
            "cpu_executed": pe_exec.cpu_executed,
            "halt_reason": pe_exec.halt_reason,
            "pid": pe_exec.pid,
            "session_id": pe_exec.session_id,
            "error": pe_exec.error,
            "gui": pe_gui,
        },
        "triangle": {
            "pixels": pe_gui.as_ref().map(|g| g.triangle_pixels).unwrap_or(0),
            "file": side_triangle.clone(),
            "width": pe_gui.as_ref().map(|g| g.width).unwrap_or(width),
            "height": pe_gui.as_ref().map(|g| g.height).unwrap_or(height),
        },
        "present": {
            "frames": pe_gui.as_ref().map(|g| g.present_frames).unwrap_or(0),
            "compositor_frames": pe_gui.as_ref().map(|g| g.compositor_frames).unwrap_or(0),
            "file": side_present.clone(),
            "display_backend": "wayland",
        },
        "graphics_pipeline": gx_json,
        "side_effects": {
            "dir": side_dir.display().to_string(),
            "triangle_file": side_triangle.clone(),
            "present_file": side_present.clone(),
        },
        "artifacts": [
            side_triangle,
            side_present,
        ],
        "failures": failures,
        "exclusions_honored": [
            "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
            "no Wine/Proton substrate; execution_backend=native",
            "no WinBox naming",
            "no full Windows compatibility claim",
            "no anti-cheat ranked pass claim",
            "mode=simulated never counts as PASS",
        ],
        "claims": {
            "full_windows_compat": false,
            "anticheat_ranked_pass": false,
            "wine_proton_used": false,
            "simulated_ok": false,
        },
    });

    write_json(&out_json, &doc);
    println!(
        "nt-graphics-verify {} mode={} → {}",
        status,
        pe_mode,
        out_json.display()
    );
    if status != "PASS" {
        for f in &failures {
            eprintln!("  FAIL: {f}");
        }
        std::process::exit(1);
    }
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
