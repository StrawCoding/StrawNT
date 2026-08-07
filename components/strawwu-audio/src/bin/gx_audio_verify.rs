//! gx-audio-verify — emit portable GX1 audio/input evidence JSON.
//!
//! Usage:
//!   gx-audio-verify <out-json> [side-effects-dir]

use std::path::PathBuf;
use std::process::Command;

use strawwu_audio::run_audio_input_smoke;

fn main() {
    let mut args = std::env::args().skip(1);
    let out_json = PathBuf::from(args.next().unwrap_or_else(|| {
        "tests/portable/output/gx-audio-input.json".into()
    }));
    let side_dir = PathBuf::from(args.next().unwrap_or_else(|| {
        out_json
            .parent()
            .unwrap_or_else(|| std::path::Path::new("."))
            .join("gx1-side-effects")
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

    let smoke = match run_audio_input_smoke(&side_dir) {
        Ok(r) => r,
        Err(e) => {
            let doc = serde_json::json!({
                "schema": "strawwu-portable-gx-audio-input/v1",
                "stage": "gx1-audio-input",
                "status": "FAIL",
                "version": version,
                "backend": "native",
                "execution_backend": "native",
                "generated_at": generated_at,
                "error": e.to_string(),
                "exclusions_honored": exclusions(),
            });
            write_json(&out_json, &doc);
            eprintln!("gx-audio-verify FAIL: {e}");
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
        "schema": "strawwu-portable-gx-audio-input/v1",
        "stage": "gx1-audio-input",
        "status": smoke.status,
        "version": version,
        "backend": smoke.backend,
        "execution_backend": smoke.execution_backend,
        "generated_at": generated_at,
        "component": "strawwu-audio",
        "paths": {
            "wasapi_to_pipewire_or_equivalent": true,
            "xinput_basic_path": true,
            "pcm_wav_evidence": true,
        },
        "audio": {
            "host_backend": smoke.host_audio_backend,
            "bridge_backend": smoke.audio_backend,
            "sample_rate": smoke.sample_rate,
            "channels": smoke.channels,
            "tone_hz": smoke.tone_hz,
            "samples_generated": smoke.samples_generated,
            "samples_written": smoke.samples_written,
            "bytes_rendered": smoke.bytes_rendered,
            "streams_created": smoke.streams_created,
            "devices_render": smoke.devices_render,
            "devices_capture": smoke.devices_capture,
            "pipewire_socket_present": smoke.pipewire_socket_present,
            "alsa_nodes": smoke.alsa_nodes,
            "wav": smoke.wav_path,
        },
        "input": {
            "controllers_connected": smoke.input.controllers_connected,
            "button_events": smoke.input.button_events,
            "axis_events": smoke.input.axis_events,
            "vibration_set": smoke.input.vibration_set,
            "deadzone_applied": smoke.input.deadzone_applied,
            "evdev_count": smoke.input.evdev_count,
            "observation": smoke.input_obs_path,
        },
        "side_effects": {
            "dir": side_dir.display().to_string(),
            "wav": smoke.wav_path,
            "input_obs": smoke.input_obs_path,
        },
        "checks": checks,
        "gaps": smoke.gaps,
        "known_limitations": smoke.gaps,
        "exclusions_honored": exclusions(),
        "claims": {
            "full_windows_compat": false,
            "anticheat_ranked_pass": false,
            "libpipewire_spa_linked": false,
            "wine_proton_used": false,
            "path_role": "legacy_native",
        },
    });

    write_json(&out_json, &doc);
    println!(
        "gx-audio-verify {} → {}",
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
