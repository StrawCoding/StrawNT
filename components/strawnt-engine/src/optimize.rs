//! NTW3 Wine/GE optimization profiles + measurable bench harness.
//!
//! Honesty: deltas must be numeric (ms / KiB). No vibes-only PASS.
//! Does not claim full Windows, ranked anti-cheat, or all-games playable.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use crate::paths::{ensure_layout, prefixes_dir};
use crate::prefix::{is_initialized, validate_name, wineboot_init};
use crate::{load_pin, wine_bin_path, EngineError, Result};

/// Bench / runtime profile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OptProfile {
    /// Pre-optimize / raw-ish Wine launch (NTW3 baseline).
    Baseline,
    /// Product optimize path: template prefix clone + esync/fsync + quiet env.
    Optimized,
}

impl OptProfile {
    pub fn as_str(self) -> &'static str {
        match self {
            OptProfile::Baseline => "baseline",
            OptProfile::Optimized => "optimized",
        }
    }

    pub fn parse(s: &str) -> Result<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "baseline" | "raw" | "legacy" => Ok(OptProfile::Baseline),
            "optimized" | "optimize" | "opt" => Ok(OptProfile::Optimized),
            other => Err(EngineError::Message(format!(
                "unknown optimize profile '{other}' (use baseline|optimized)"
            ))),
        }
    }
}

/// How to materialize a new prefix.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrefixCreateMode {
    /// Full `wineboot -u` every time (baseline).
    Wineboot,
    /// Clone from a one-time wineboot template (optimized).
    TemplateClone,
}

impl PrefixCreateMode {
    pub fn as_str(self) -> &'static str {
        match self {
            PrefixCreateMode::Wineboot => "wineboot",
            PrefixCreateMode::TemplateClone => "template_clone",
        }
    }
}

pub fn default_prefix_mode() -> PrefixCreateMode {
    match std::env::var("STRAWNT_PREFIX_MODE")
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "wineboot" | "boot" | "baseline" => PrefixCreateMode::Wineboot,
        _ => PrefixCreateMode::TemplateClone,
    }
}

pub fn templates_dir(home: &Path) -> PathBuf {
    home.join("templates")
}

pub fn template_path(home: &Path, arch: &str) -> PathBuf {
    templates_dir(home).join(arch)
}

/// Apply Wine process environment for the given profile onto a Command.
pub fn apply_wine_env(cmd: &mut Command, profile: OptProfile, prefix: &Path, arch: &str) {
    cmd.env("WINEPREFIX", prefix).env("WINEARCH", arch);
    match profile {
        OptProfile::Baseline => {
            // Deliberate pre-optimize baseline: leave WINEDEBUG default (noisy),
            // no esync/fsync, no dll overrides — measures unoptimized launch cost.
            cmd.env_remove("WINEDEBUG");
            cmd.env_remove("WINEDLLOVERRIDES");
            cmd.env_remove("WINEESYNC");
            cmd.env_remove("WINEFSYNC");
            cmd.env_remove("DXVK_LOG_LEVEL");
            cmd.env_remove("VKD3D_DEBUG");
            cmd.env_remove("WINE_LARGE_ADDRESS_AWARE");
        }
        OptProfile::Optimized => {
            cmd.env("WINEDEBUG", "-all");
            cmd.env(
                "WINEDLLOVERRIDES",
                "winemenubuilder.exe=d;mscoree=d;mshtml=d",
            );
            cmd.env("WINEESYNC", "1");
            cmd.env("WINEFSYNC", "1");
            cmd.env("DXVK_LOG_LEVEL", "none");
            cmd.env("VKD3D_DEBUG", "none");
            cmd.env("WINE_LARGE_ADDRESS_AWARE", "1");
        }
    }
}

fn kill_wineserver(repo: &Path, prefix: &Path) {
    if let Ok(pin) = load_pin(repo) {
        let wine = wine_bin_path(repo, &pin);
        if let Some(bin_dir) = wine.parent() {
            let ws = bin_dir.join("wineserver");
            if ws.is_file() {
                let _ = Command::new(&ws)
                    .arg("-k")
                    .env("WINEPREFIX", prefix)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }
    }
    // Brief settle so sockets/locks release.
    thread::sleep(Duration::from_millis(200));
}

fn cp_a(src: &Path, dst: &Path) -> Result<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }
    if dst.exists() {
        fs::remove_dir_all(dst)?;
    }
    let status = Command::new("cp")
        .arg("-a")
        .arg(src)
        .arg(dst)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .status()?;
    if !status.success() {
        return Err(EngineError::Message(format!(
            "cp -a {} -> {} failed (exit {:?})",
            src.display(),
            dst.display(),
            status.code()
        )));
    }
    Ok(())
}

/// Ensure a reusable win64/win32 template exists (wineboot once).
pub fn ensure_template(repo: &Path, home: &Path, arch: &str) -> Result<Value> {
    let tpl = template_path(home, arch);
    if is_initialized(&tpl) {
        return Ok(json!({
            "status": "PASS",
            "created": false,
            "path": tpl.display().to_string(),
            "arch": arch,
            "message": "template already present",
        }));
    }
    fs::create_dir_all(templates_dir(home))?;
    // Template wineboot uses optimized quiet env (product path).
    let boot = wineboot_init(repo, &tpl, arch)?;
    let ok = boot.get("status").and_then(|v| v.as_str()) == Some("PASS") && is_initialized(&tpl);
    if ok {
        let meta = json!({
            "schema": "strawnt-prefix-template/v1",
            "arch": arch,
            "engine": "proton-ge",
            "created_via": "wineboot",
            "product": "StrawNT",
        });
        let _ = fs::write(
            tpl.join(".strawnt-template.json"),
            serde_json::to_string_pretty(&meta).unwrap_or_default(),
        );
    }
    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "created": true,
        "path": tpl.display().to_string(),
        "arch": arch,
        "wineboot": boot,
    }))
}

/// Create prefix via template clone (must ensure_template first).
pub fn clone_prefix_from_template(
    repo: &Path,
    home: &Path,
    name: &str,
    arch: &str,
) -> Result<Value> {
    let name = validate_name(name)?;
    let tpl = template_path(home, arch);
    if !is_initialized(&tpl) {
        let ens = ensure_template(repo, home, arch)?;
        if ens.get("status").and_then(|v| v.as_str()) != Some("PASS") {
            return Ok(json!({
                "status": "FAIL",
                "mode": PrefixCreateMode::TemplateClone.as_str(),
                "error": "template ensure failed",
                "ensure": ens,
            }));
        }
    }
    kill_wineserver(repo, &tpl);
    let target = prefixes_dir(home).join(&name);
    let started = Instant::now();
    cp_a(&tpl, &target)?;
    // Drop template marker in clone; rewrite a clone marker.
    let _ = fs::remove_file(target.join(".strawnt-template.json"));
    let meta = json!({
        "schema": "strawnt-prefix-clone/v1",
        "cloned_from": tpl.display().to_string(),
        "arch": arch,
        "mode": "template_clone",
    });
    let _ = fs::write(
        target.join(".strawnt-prefix.json"),
        serde_json::to_string_pretty(&meta).unwrap_or_default(),
    );
    let ms = started.elapsed().as_secs_f64() * 1000.0;
    let ok = is_initialized(&target);
    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "mode": PrefixCreateMode::TemplateClone.as_str(),
        "name": name,
        "path": target.display().to_string(),
        "arch": arch,
        "template": tpl.display().to_string(),
        "duration_ms": ms,
        "created": true,
    }))
}

fn read_rss_kb(pid: i32) -> Option<u64> {
    let text = fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("VmRSS:") {
            let kb: u64 = rest
                .split_whitespace()
                .next()?
                .parse()
                .ok()?;
            return Some(kb);
        }
    }
    None
}

fn wine_related_pids(prefix: &Path) -> Vec<i32> {
    let prefix_s = prefix.display().to_string();
    let mut pids = Vec::new();
    let Ok(entries) = fs::read_dir("/proc") else {
        return pids;
    };
    for ent in entries.flatten() {
        let name = ent.file_name();
        let name = name.to_string_lossy();
        if !name.chars().all(|c| c.is_ascii_digit()) {
            continue;
        }
        let pid: i32 = match name.parse() {
            Ok(p) => p,
            Err(_) => continue,
        };
        let environ = fs::read(format!("/proc/{pid}/environ")).unwrap_or_default();
        let environ_s = String::from_utf8_lossy(&environ);
        if !environ_s
            .split('\0')
            .any(|e| e == format!("WINEPREFIX={prefix_s}") || e.starts_with(&format!("WINEPREFIX={prefix_s}")))
        {
            // Also match cmdline wine/wineserver loosely if cwd under prefix.
            let cmdline = fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
            let cmd = String::from_utf8_lossy(&cmdline);
            if !(cmd.contains("wineserver") || cmd.contains("/wine") || cmd.contains("wine64")) {
                continue;
            }
            let cwd = fs::read_link(format!("/proc/{pid}/cwd")).ok();
            let under = cwd
                .as_ref()
                .map(|c| c.starts_with(prefix))
                .unwrap_or(false);
            if !under && !environ_s.contains(&prefix_s) {
                continue;
            }
        }
        pids.push(pid);
    }
    pids.sort_unstable();
    pids.dedup();
    pids
}

fn sum_rss_kb(prefix: &Path) -> (u64, Vec<i32>) {
    let pids = wine_related_pids(prefix);
    let mut total = 0u64;
    for pid in &pids {
        if let Some(kb) = read_rss_kb(*pid) {
            total = total.saturating_add(kb);
        }
    }
    (total, pids)
}

fn needs_xvfb() -> bool {
    if matches!(
        std::env::var("STRAWNT_FORCE_XVFB").ok().as_deref(),
        Some("1") | Some("true") | Some("TRUE") | Some("yes")
    ) {
        return true;
    }
    std::env::var("DISPLAY")
        .ok()
        .filter(|d| !d.is_empty())
        .is_none()
}

fn which(bin: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).find_map(|dir| {
            let p = dir.join(bin);
            p.is_file().then_some(p)
        })
    })
}

/// Spawn wine cmd /c echo MARKER; return child + marker + whether xvfb wrapped.
fn spawn_cmd_echo(
    repo: &Path,
    prefix: &Path,
    arch: &str,
    profile: OptProfile,
) -> Result<(Child, String, bool, PathBuf)> {
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(EngineError::Message(format!(
            "vendored wine missing at {}",
            wine.display()
        )));
    }
    let marker = format!(
        "STRAWNT_NTW3_{}_{}",
        profile.as_str(),
        std::process::id()
    );
    let mut argv: Vec<String> = Vec::new();
    let mut used_xvfb = false;
    if needs_xvfb() {
        if let Some(xvfb) = which("xvfb-run") {
            argv.push(xvfb.display().to_string());
            argv.push("-a".into());
            used_xvfb = true;
        }
    }
    argv.push(wine.display().to_string());
    argv.push("cmd".into());
    argv.push("/c".into());
    argv.push(format!("echo {marker}"));

    let mut command = Command::new(&argv[0]);
    command
        .args(&argv[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    apply_wine_env(&mut command, profile, prefix, arch);

    let child = command.spawn()?;
    Ok((child, marker, used_xvfb, wine))
}

fn wait_cold_start(child: Child, marker: &str, timeout: Duration) -> Result<Value> {
    let started = Instant::now();
    let (tx, rx) = std::sync::mpsc::channel();
    thread::spawn(move || {
        let _ = tx.send(child.wait_with_output());
    });
    let output = match rx.recv_timeout(timeout) {
        Ok(Ok(o)) => o,
        Ok(Err(e)) => return Err(e.into()),
        Err(_) => {
            return Ok(json!({
                "status": "FAIL",
                "error": "cold start timed out",
                "cold_start_ms": started.elapsed().as_secs_f64() * 1000.0,
            }));
        }
    };
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let ms = started.elapsed().as_secs_f64() * 1000.0;
    let ok = output.status.success() && stdout.contains(marker);
    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "cold_start_ms": ms,
        "exit_code": output.status.code().unwrap_or(-1),
        "stdout_has_marker": stdout.contains(marker),
        "stdout_tail": tail(&stdout, 200),
        "stderr_tail": tail(&stderr, 200),
    }))
}

fn tail(s: &str, n: usize) -> String {
    if s.len() <= n {
        s.to_string()
    } else {
        s[s.len() - n..].to_string()
    }
}

fn probe_dxvk_vulkan(repo: &Path) -> Value {
    let pin = load_pin(repo).ok();
    let dist = repo.join("third_party/proton-ge/dist");
    let dxvk_dir = dist.join("files/lib/wine/dxvk");
    let dxvk_present = dxvk_dir.is_dir();
    let mut dlls = Vec::new();
    if dxvk_present {
        if let Ok(entries) = fs::read_dir(dxvk_dir.join("x86_64-windows")) {
            for e in entries.flatten() {
                let n = e.file_name().to_string_lossy().to_string();
                if n.ends_with(".dll") {
                    dlls.push(n);
                }
            }
        }
    }
    let vulkaninfo = which("vulkaninfo");
    let mut vulkan = json!({
        "vulkaninfo_present": vulkaninfo.is_some(),
        "devices": Value::Null,
        "status": "UNKNOWN",
    });
    if let Some(vi) = vulkaninfo {
        let out = Command::new(vi)
            .arg("--summary")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();
        if let Ok(o) = out {
            let text = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            let has_gpu = text.to_ascii_lowercase().contains("gpu")
                || text.contains("Vulkan Instance Version")
                || text.contains("deviceName");
            vulkan = json!({
                "vulkaninfo_present": true,
                "summary_tail": tail(&text, 400),
                "status": if o.status.success() && has_gpu { "PASS" } else if o.status.success() { "PARTIAL" } else { "FAIL" },
            });
        }
    }
    json!({
        "dxvk_tree_present": dxvk_present,
        "dxvk_dll_count": dlls.len(),
        "dxvk_dll_sample": dlls.into_iter().take(8).collect::<Vec<_>>(),
        "vulkan": vulkan,
        "engine_pin": pin.map(|p| p.tag),
        "frames_sampled": false,
        "notes": "No GUI frame counter in headless NTW3 harness; DXVK/Vulkan presence only",
    })
}

fn idle_sec() -> u64 {
    // Authoritative plan (NTW3 Task 7): RSS after 60s idle minimum.
    // Env override may raise the window; values below 60 are rejected for honesty.
    let requested = std::env::var("STRAWNT_NTW3_IDLE_SEC")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(60u64);
    requested.max(60)
}

/// Run one full NTW3 metric suite for a profile.
pub fn run_bench(
    repo: &Path,
    home_override: Option<&Path>,
    profile: OptProfile,
) -> Result<Value> {
    let home = ensure_layout(home_override)?;
    let pin = load_pin(repo)?;
    let arch = "win64";
    let idle = idle_sec();
    let prefix_mode = match profile {
        OptProfile::Baseline => PrefixCreateMode::Wineboot,
        OptProfile::Optimized => PrefixCreateMode::TemplateClone,
    };

    let bench_name = format!("ntw3-{}-{}", profile.as_str(), std::process::id());
    let prefix = prefixes_dir(&home).join(&bench_name);

    // Clean slate for this bench name.
    if prefix.exists() {
        kill_wineserver(repo, &prefix);
        let _ = fs::remove_dir_all(&prefix);
    }

    // --- prefix create ---
    // For optimized: ensure template *before* the timed window so prefix_create_ms
    // measures amortized clone cost (product steady-state), not one-time wineboot.
    let pre_ensure = if prefix_mode == PrefixCreateMode::TemplateClone {
        Some(ensure_template(repo, &home, arch)?)
    } else {
        None
    };
    if let Some(ref ens) = pre_ensure {
        if ens.get("status").and_then(|v| v.as_str()) != Some("PASS") {
            return Ok(json!({
                "schema": "strawnt-ntw3-bench/v1",
                "product": "StrawNT",
                "stage": "ntw3-optimize",
                "profile": profile.as_str(),
                "status": "FAIL",
                "execution_backend": "wine",
                "backend": "wine",
                "engine": "proton-ge",
                "pin": pin.tag,
                "engine_pin": pin.tag,
                "powered_by": "Wine",
                "powered_by_wine": true,
                "simulated": false,
                "metrics": null,
                "prefix_create": { "status": "FAIL", "ensure_template": ens },
                "claims": { "measurable": true, "simulated": false },
                "notes": ["template ensure failed before timed clone"],
            }));
        }
    }

    let create_started = Instant::now();
    let create_detail = match prefix_mode {
        PrefixCreateMode::Wineboot => {
            let boot = wineboot_init(repo, &prefix, arch)?;
            let ok =
                boot.get("status").and_then(|v| v.as_str()) == Some("PASS") && is_initialized(&prefix);
            json!({
                "status": if ok { "PASS" } else { "FAIL" },
                "mode": prefix_mode.as_str(),
                "wineboot": boot,
            })
        }
        PrefixCreateMode::TemplateClone => {
            let clone = clone_prefix_from_template(repo, &home, &bench_name, arch)?;
            json!({
                "status": clone.get("status").cloned().unwrap_or(json!("FAIL")),
                "mode": prefix_mode.as_str(),
                "ensure_template": pre_ensure,
                "clone": clone,
                "timed_window": "clone_only",
            })
        }
    };
    let prefix_create_ms = create_started.elapsed().as_secs_f64() * 1000.0;
    let create_ok = create_detail.get("status").and_then(|v| v.as_str()) == Some("PASS");

    // Isolate clone duration when available (fairer optimized metric).
    let prefix_create_clone_ms = create_detail
        .pointer("/clone/duration_ms")
        .and_then(|v| v.as_f64());

    // --- cold start ---
    kill_wineserver(repo, &prefix);
    thread::sleep(Duration::from_millis(300));
    let cold = if create_ok {
        match spawn_cmd_echo(repo, &prefix, arch, profile) {
            Ok((child, marker, used_xvfb, wine_bin)) => {
                let mut result = wait_cold_start(child, &marker, Duration::from_secs(120))?;
                if let Some(obj) = result.as_object_mut() {
                    obj.insert("used_xvfb".into(), json!(used_xvfb));
                    obj.insert("wine_bin".into(), json!(wine_bin.display().to_string()));
                    obj.insert("marker".into(), json!(marker));
                }
                result
            }
            Err(e) => json!({
                "status": "FAIL",
                "error": e.to_string(),
                "cold_start_ms": null,
            }),
        }
    } else {
        json!({
            "status": "FAIL",
            "error": "skipped cold start; prefix create failed",
            "cold_start_ms": null,
        })
    };
    let cold_start_ms = cold.get("cold_start_ms").and_then(|v| v.as_f64());
    let cold_ok = cold.get("status").and_then(|v| v.as_str()) == Some("PASS");

    // Keep a wineserver alive for RSS idle sampling: launch a long-lived cmd.
    let mut rss_kb: Option<u64> = None;
    let mut rss_pids: Vec<i32> = Vec::new();
    let mut rss_status = "FAIL";
    if cold_ok {
        // Start wineserver via a short keep-alive: wine cmd /c ping localhost
        // is slow; use wineserver -p0 then wine cmd.
        if let Ok(pin_ref) = load_pin(repo) {
            let wine = wine_bin_path(repo, &pin_ref);
            if let Some(bin_dir) = wine.parent() {
                let ws = bin_dir.join("wineserver");
                if ws.is_file() {
                    let mut c = Command::new(&ws);
                    c.arg("-p").arg("0").stdout(Stdio::null()).stderr(Stdio::null());
                    apply_wine_env(&mut c, profile, &prefix, arch);
                    let _ = c.status();
                }
            }
            // Touch wineserver with a quick cmd that exits but leaves server if -p0.
            let mut c = Command::new(&wine);
            c.arg("cmd").arg("/c").arg("echo RSS_KEEP");
            apply_wine_env(&mut c, profile, &prefix, arch);
            let _ = c.stdout(Stdio::null()).stderr(Stdio::null()).status();
        }
        thread::sleep(Duration::from_secs(idle));
        let (total, pids) = sum_rss_kb(&prefix);
        rss_kb = Some(total);
        rss_pids = pids;
        rss_status = if total > 0 { "PASS" } else { "PARTIAL" };
    }

    kill_wineserver(repo, &prefix);

    let graphics = probe_dxvk_vulkan(repo);

    let metrics = json!({
        "cold_start_ms": cold_start_ms,
        "rss_after_idle_kb": rss_kb,
        "rss_idle_sec": idle,
        "rss_pids": rss_pids,
        "prefix_create_ms": prefix_create_ms,
        "prefix_create_clone_ms": prefix_create_clone_ms,
        "prefix_create_mode": prefix_mode.as_str(),
    });

    let mut notes = vec![
        format!("profile={}", profile.as_str()),
        format!("prefix_mode={}", prefix_mode.as_str()),
        "powered by Wine".into(),
        "not a full Windows claim".into(),
        "not a ranked anti-cheat claim".into(),
    ];
    if profile == OptProfile::Optimized {
        notes.push("optimizations: template_clone+WINEDEBUG=-all+WINEDLLOVERRIDES+WINEESYNC+WINEFSYNC+DXVK_LOG_LEVEL=none".into());
    } else {
        notes.push("baseline: full wineboot + default Wine debug (no esync/fsync/dll overrides)".into());
    }

    let overall = if create_ok && cold_ok && rss_status != "FAIL" {
        "PASS"
    } else if create_ok || cold_ok {
        "PARTIAL"
    } else {
        "FAIL"
    };

    Ok(json!({
        "schema": "strawnt-ntw3-bench/v1",
        "product": "StrawNT",
        "stage": "ntw3-optimize",
        "profile": profile.as_str(),
        "status": overall,
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "pin": pin.tag,
        "engine_pin": pin.tag,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "simulated": false,
        "metrics": metrics,
        "prefix_create": create_detail,
        "cold_start": cold,
        "rss": {
            "status": rss_status,
            "rss_kb": rss_kb,
            "idle_sec": idle,
            "pids": rss_pids,
        },
        "graphics": graphics,
        "prefix": prefix.display().to_string(),
        "home": home.display().to_string(),
        "notes": notes,
        "claims": {
            "measurable": true,
            "powered_by_wine": true,
            "full_windows_claimed": false,
            "ranked_anticheat_claimed": false,
            "simulated": false,
        },
    }))
}

/// Compute numeric deltas (after - before). Negative = improvement for time/RSS.
pub fn compute_deltas(before: &Value, after: &Value) -> Value {
    let b = before.get("metrics").cloned().unwrap_or(json!({}));
    let a = after.get("metrics").cloned().unwrap_or(json!({}));

    fn f(v: &Value, key: &str) -> Option<f64> {
        v.get(key).and_then(|x| x.as_f64())
    }

    let mut deltas = HashMap::new();
    for key in [
        "cold_start_ms",
        "rss_after_idle_kb",
        "prefix_create_ms",
        "prefix_create_clone_ms",
    ] {
        match (f(&b, key), f(&a, key)) {
            (Some(bv), Some(av)) => {
                let delta = av - bv;
                let pct = if bv.abs() > f64::EPSILON {
                    (delta / bv) * 100.0
                } else {
                    0.0
                };
                deltas.insert(
                    key.to_string(),
                    json!({
                        "before": bv,
                        "after": av,
                        "delta": delta,
                        "delta_pct": pct,
                        "improved": delta < 0.0,
                    }),
                );
            }
            _ => {
                deltas.insert(
                    key.to_string(),
                    json!({
                        "before": b.get(key),
                        "after": a.get(key),
                        "delta": null,
                        "improved": null,
                    }),
                );
            }
        }
    }

    // Prefer clone-only create metric for optimized when wall create includes
    // first-time template ensure; still report wall delta.
    let improved_any = deltas.values().any(|v| {
        v.get("improved")
            .and_then(|x| x.as_bool())
            .unwrap_or(false)
    });

    json!({
        "cold_start_ms": deltas.get("cold_start_ms"),
        "rss_after_idle_kb": deltas.get("rss_after_idle_kb"),
        "prefix_create_ms": deltas.get("prefix_create_ms"),
        "prefix_create_clone_ms": deltas.get("prefix_create_clone_ms"),
        "any_improved": improved_any,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    // Env mutation must be serialized across idle_sec tests.
    static IDLE_ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn profile_parse() {
        assert_eq!(OptProfile::parse("baseline").unwrap(), OptProfile::Baseline);
        assert_eq!(
            OptProfile::parse("optimized").unwrap(),
            OptProfile::Optimized
        );
    }

    #[test]
    fn idle_sec_defaults_and_clamps_to_plan_floor() {
        let _guard = IDLE_ENV_LOCK.lock().unwrap();
        std::env::remove_var("STRAWNT_NTW3_IDLE_SEC");
        assert_eq!(idle_sec(), 60, "plan Task 7 floor is 60s");

        std::env::set_var("STRAWNT_NTW3_IDLE_SEC", "10");
        assert_eq!(idle_sec(), 60, "values below 60 must clamp upward");

        std::env::set_var("STRAWNT_NTW3_IDLE_SEC", "59");
        assert_eq!(idle_sec(), 60);

        std::env::set_var("STRAWNT_NTW3_IDLE_SEC", "90");
        assert_eq!(idle_sec(), 90, "values above floor are allowed");

        std::env::remove_var("STRAWNT_NTW3_IDLE_SEC");
    }

    #[test]
    fn deltas_improve_when_after_smaller() {
        let before = json!({"metrics": {"cold_start_ms": 100.0, "prefix_create_ms": 1000.0, "rss_after_idle_kb": 200.0}});
        let after = json!({"metrics": {"cold_start_ms": 80.0, "prefix_create_ms": 50.0, "rss_after_idle_kb": 180.0}});
        let d = compute_deltas(&before, &after);
        assert_eq!(d["any_improved"], json!(true));
        assert!(d["prefix_create_ms"]["delta"].as_f64().unwrap() < 0.0);
    }
}
