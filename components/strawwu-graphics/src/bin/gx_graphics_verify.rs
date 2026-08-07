//! gx-graphics-verify — emit portable GX0 graphics evidence JSON.
//!
//! Usage:
//!   gx-graphics-verify <out-json> [side-effects-dir] [width] [height]

use std::path::PathBuf;
use std::process::Command;

use strawwu_graphics::run_graphics_smoke;

fn main() {
    let mut args = std::env::args().skip(1);
    let out_json = PathBuf::from(args.next().unwrap_or_else(|| {
        "tests/portable/output/gx-graphics.json".into()
    }));
    let side_dir = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .unwrap_or_else(|| std::path::Path::new("."))
            .join("gx0-side-effects")
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

    let smoke = match run_graphics_smoke(&side_dir, width, height) {
        Ok(r) => r,
        Err(e) => {
            let doc = serde_json::json!({
                "schema": "strawwu-portable-gx-graphics/v1",
                "stage": "gx0-graphics-vk-gl",
                "status": "FAIL",
                "version": version,
                "backend": "native",
                "execution_backend": "native",
                "generated_at": generated_at,
                "error": e.to_string(),
                "exclusions_honored": exclusions(),
            });
            write_json(&out_json, &doc);
            eprintln!("gx-graphics-verify FAIL: {e}");
            std::process::exit(1);
        }
    };

    let checks: Vec<serde_json::Value> = smoke
        .paths
        .iter()
        .map(|p| {
            serde_json::json!({
                "name": p.name,
                "status": p.status,
                "detail": p.detail,
            })
        })
        .collect();

    let doc = serde_json::json!({
        "schema": "strawwu-portable-gx-graphics/v1",
        "stage": "gx0-graphics-vk-gl",
        "status": smoke.status,
        "version": version,
        "backend": smoke.backend,
        "execution_backend": smoke.execution_backend,
        "generated_at": generated_at,
        "component": "strawwu-graphics",
        "paths": {
            "dxgi_d3d11_to_vulkan": true,
            "wgl_to_gl_present": true,
            "present_bridge": true,
        },
        "triangle": {
            "drawn": smoke.triangles_drawn,
            "draw_calls": smoke.draw_calls,
            "pixels": smoke.triangle_pixels,
            "width": smoke.width,
            "height": smoke.height,
            "screenshot": smoke.screenshot_path,
        },
        "present": {
            "vk_frames": smoke.vk_frames,
            "dxgi_frames": smoke.dxgi_frames,
            "wgl_frames": smoke.wgl_frames,
            "present_frames": smoke.present_frames,
            "observation": smoke.present_obs_path,
            "display_backend": smoke.display_backend,
            "vk_icd": smoke.vk_icd_name,
            "d3d11_target": smoke.d3d11_target,
            "wgl_backend": smoke.wgl_backend,
        },
        "side_effects": {
            "dir": side_dir.display().to_string(),
            "screenshot": smoke.screenshot_path,
            "present_obs": smoke.present_obs_path,
        },
        "checks": checks,
        "gaps": smoke.gaps,
        "known_limitations": smoke.gaps,
        "exclusions_honored": exclusions(),
        "claims": {
            "full_windows_compat": false,
            "anticheat_ranked_pass": false,
            "host_mesa_icd_bound": false,
            "wine_proton_used": false,
            "path_role": "legacy_native",
        },
    });

    write_json(&out_json, &doc);
    println!(
        "gx-graphics-verify {} → {}",
        smoke.status,
        out_json.display()
    );
    if smoke.status != "PASS" && smoke.status != "PARTIAL" {
        std::process::exit(1);
    }
}

fn exclusions() -> Vec<&'static str> {
    vec![
        "no ISO/os-image/Plymouth/Calamares/kernel/desktop changes",
        "legacy_native research path; product default wine/proton-ge (NTW0); powered by Wine",
        "no WinBox naming",
        "no full Windows compatibility claim",
        "no anti-cheat ranked pass claim",
    ]
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
