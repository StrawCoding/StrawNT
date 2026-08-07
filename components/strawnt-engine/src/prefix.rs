//! Prefix create / list — straw-wine sw1 patterns on vendored Proton-GE.

use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::paths::{ensure_layout, prefixes_dir, read_index, write_index};
use crate::{load_pin, wine_bin_path, EngineError, Result};

pub fn validate_name(name: &str) -> Result<String> {
    let bytes = name.as_bytes();
    if bytes.is_empty() || bytes.len() > 64 {
        return Err(EngineError::Message(format!(
            "invalid prefix name '{name}' (use [A-Za-z0-9._-], start alnum, max 64)"
        )));
    }
    let first = bytes[0];
    if !(first.is_ascii_alphanumeric()) {
        return Err(EngineError::Message(format!(
            "invalid prefix name '{name}' (must start with alphanumeric)"
        )));
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
    {
        return Err(EngineError::Message(format!(
            "invalid prefix name '{name}' (use [A-Za-z0-9._-], start alnum, max 64)"
        )));
    }
    Ok(name.to_string())
}

pub fn prefix_path(home: &Path, name: &str) -> Result<PathBuf> {
    let name = validate_name(name)?;
    Ok(prefixes_dir(home).join(name))
}

pub fn is_initialized(path: &Path) -> bool {
    path.join("system.reg").is_file() || path.join("drive_c").is_dir()
}

fn needs_xvfb() -> bool {
    if env_truthy("STRAWNT_FORCE_XVFB") || env_truthy("STRAWWINE_FORCE_XVFB") {
        return true;
    }
    if env_truthy("STRAWNT_NO_XVFB") || env_truthy("STRAWWINE_NO_XVFB") {
        return false;
    }
    std::env::var("DISPLAY")
        .ok()
        .filter(|d| !d.is_empty())
        .is_none()
}

fn env_truthy(key: &str) -> bool {
    matches!(
        std::env::var(key).ok().as_deref(),
        Some("1") | Some("true") | Some("TRUE") | Some("yes")
    )
}

fn which(bin: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).find_map(|dir| {
            let p = dir.join(bin);
            p.is_file().then_some(p)
        })
    })
}

fn tail(s: &str, n: usize) -> String {
    if s.len() <= n {
        s.to_string()
    } else {
        s[s.len() - n..].to_string()
    }
}

/// Initialize a Wine prefix via vendored `wine wineboot -u` (xvfb when needed).
pub fn wineboot_init(repo: &Path, prefix: &Path, arch: &str) -> Result<Value> {
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(EngineError::Message(format!(
            "vendored wine missing at {}; run scripts/fetch-proton-ge.sh",
            wine.display()
        )));
    }
    fs::create_dir_all(prefix)?;

    let wine_s = wine.display().to_string();
    let mut argv: Vec<String> = Vec::new();
    let mut used_xvfb = false;
    if needs_xvfb() {
        if let Some(xvfb) = which("xvfb-run") {
            argv.push(xvfb.display().to_string());
            argv.push("-a".into());
            used_xvfb = true;
        }
    }
    argv.push(wine_s.clone());
    argv.push("wineboot".into());
    argv.push("-u".into());

    let started = Instant::now();
    let mut command = Command::new(&argv[0]);
    command
        .args(&argv[1..])
        .env("WINEPREFIX", prefix)
        .env("WINEARCH", arch)
        .env("WINEDEBUG", "-all")
        .env("WINEDLLOVERRIDES", "winemenubuilder.exe=d")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    // Run with a wall-clock timeout via thread join.
    let (tx, rx) = std::sync::mpsc::channel();
    let handle = std::thread::spawn(move || {
        let out = command.output();
        let _ = tx.send(out);
    });
    let output = match rx.recv_timeout(Duration::from_secs(180)) {
        Ok(Ok(o)) => o,
        Ok(Err(e)) => return Err(e.into()),
        Err(_) => {
            // Best-effort: kill wineserver for this prefix.
            if let Some(ws) = wine.parent().map(|p| p.join("wineserver")) {
                let _ = Command::new(ws)
                    .arg("-k")
                    .env("WINEPREFIX", prefix)
                    .output();
            }
            let _ = handle.join();
            return Err(EngineError::Message(
                "wineboot timed out after 180s".into(),
            ));
        }
    };
    let _ = handle.join();

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let exit_code = output.status.code().unwrap_or(-1);
    let ok = exit_code == 0 && is_initialized(prefix);
    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "exit_code": exit_code,
        "used_xvfb": used_xvfb,
        "duration_sec": started.elapsed().as_secs_f64(),
        "stdout_tail": tail(&stdout, 400),
        "stderr_tail": tail(&stderr, 400),
        "command": argv,
        "wine_bin": wine.display().to_string(),
        "pin": pin.tag,
    }))
}

pub fn create_prefix(
    repo: &Path,
    name: &str,
    arch: &str,
    force: bool,
    home_override: Option<&Path>,
) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let name = validate_name(name)?;
    let target = prefixes_dir(&root).join(&name);

    if target.exists() && is_initialized(&target) && !force {
        return Ok(json!({
            "status": "PASS",
            "name": name,
            "path": target.display().to_string(),
            "arch": arch,
            "created": false,
            "message": "prefix already exists",
            "execution_backend": "wine",
            "backend": "wine",
            "engine": "proton-ge",
            "powered_by": "Wine",
            "powered_by_wine": true,
        }));
    }

    let boot = wineboot_init(repo, &target, arch)?;
    let ok = boot.get("status").and_then(|v| v.as_str()) == Some("PASS") && is_initialized(&target);
    let pin = load_pin(repo)?;
    let now = unix_now_iso();

    let mut index = read_index(&root)?;
    index["prefixes"][&name] = json!({
        "path": target.display().to_string(),
        "arch": arch,
        "created_at": now,
        "engine": "proton-ge",
        "pin": pin.tag,
        "execution_backend": "wine",
        "last_status": if ok { "PASS" } else { "FAIL" },
    });
    write_index(&root, &index)?;

    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "name": name,
        "path": target.display().to_string(),
        "arch": arch,
        "created": true,
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "pin": pin.tag,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "wineboot": boot,
        "home": root.display().to_string(),
    }))
}

pub fn list_prefixes(home_override: Option<&Path>) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let index = read_index(&root)?;
    let mut discovered = Vec::new();
    let pdir = prefixes_dir(&root);
    if pdir.is_dir() {
        let mut entries: Vec<_> = fs::read_dir(&pdir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir())
            .collect();
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let name = e.file_name().to_string_lossy().to_string();
            let path = e.path();
            let meta = index
                .get("prefixes")
                .and_then(|p| p.get(&name))
                .cloned()
                .unwrap_or(json!({}));
            discovered.push(json!({
                "name": name,
                "path": path.display().to_string(),
                "initialized": is_initialized(&path),
                "meta": meta,
            }));
        }
    }
    Ok(json!({
        "status": "PASS",
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "count": discovered.len(),
        "prefixes": discovered,
        "home": root.display().to_string(),
    }))
}

fn unix_now_iso() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{secs}")
}
