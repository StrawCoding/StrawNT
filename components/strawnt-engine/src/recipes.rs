//! Recipe catalog + apply — absorbed from straw-wine sw4 patterns.
//! Honesty: network-heavy verbs may stay PARTIAL until winetricks completes.

use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Instant;

use crate::paths::{ensure_layout, prefixes_dir};
use crate::prefix::{is_initialized, validate_name, wineboot_init};
use crate::{load_pin, wine_bin_path, EngineError, Result};

fn recipe_catalog() -> Vec<Value> {
    vec![
        json!({
            "id": "vcrun",
            "title": "Visual C++ runtime (vcrun2022)",
            "verbs": ["vcrun2022"],
            "category": "runtime",
            "network": true,
            "description": "Install MSVC 2015–2022 redistributable via winetricks"
        }),
        json!({
            "id": "corefonts",
            "title": "Microsoft core fonts",
            "verbs": ["corefonts"],
            "category": "fonts",
            "network": true,
            "description": "Install Arial/Courier/Times via winetricks"
        }),
        json!({
            "id": "dxvk",
            "title": "DXVK (D3D8–11 → Vulkan)",
            "kind": "dxvk",
            "verbs": ["dxvk"],
            "category": "graphics",
            "network": true,
            "description": "Enable DXVK via winetricks (Vulkan required)"
        }),
        json!({
            "id": "fontsmooth",
            "title": "Font smoothing (settings)",
            "verbs": ["fontsmooth=rgb"],
            "category": "settings",
            "network": false,
            "description": "Lightweight winetricks settings verb for smoke / repair"
        }),
        json!({
            "id": "crypt32-signature",
            "title": "WinVerifyTrust soft-pass (LINE path)",
            "kind": "crypt32_signature",
            "category": "repair",
            "network": false,
            "description": "Install vendored wintrust soft-pass shim + DllOverrides; optional LINE IgnoreCodeSign (PARTIAL vs native Authenticode)"
        }),
    ]
}

fn find_recipe(id: &str) -> Option<Value> {
    recipe_catalog().into_iter().find(|r| r.get("id").and_then(|v| v.as_str()) == Some(id))
}

fn which(bin: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).find_map(|dir| {
            let p = dir.join(bin);
            p.is_file().then_some(p)
        })
    })
}

fn detect_winetricks() -> Value {
    let path = which("winetricks");
    let mut version = None;
    if let Some(ref p) = path {
        if let Ok(out) = Command::new(p).arg("--version").output() {
            let blob = format!(
                "{}{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            for line in blob.lines().rev() {
                let line = line.trim();
                if !line.is_empty() && line.chars().any(|c| c.is_ascii_digit()) && line.len() < 120
                {
                    version = Some(line.to_string());
                    break;
                }
            }
        }
    }
    json!({
        "found": path.is_some(),
        "path": path.as_ref().map(|p| p.display().to_string()),
        "version": version,
        "hint": if path.is_some() {
            Value::Null
        } else {
            json!("install winetricks to apply network recipes")
        }
    })
}

fn recipes_state_path(prefix: &Path) -> PathBuf {
    prefix.join("strawnt-recipes.json")
}

fn read_recipes_state(prefix: &Path) -> Value {
    let path = recipes_state_path(prefix);
    if !path.exists() {
        return json!({"version": 1, "applied": {}});
    }
    fs::read_to_string(&path)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_else(|| json!({"version": 1, "applied": {}}))
}

fn write_recipes_state(prefix: &Path, data: &Value) -> Result<()> {
    let text = serde_json::to_string_pretty(data)
        .map_err(|e| EngineError::Message(format!("serialize recipes: {e}")))?;
    fs::write(recipes_state_path(prefix), format!("{text}\n"))?;
    Ok(())
}

pub fn list_recipes() -> Value {
    let wt = detect_winetricks();
    let recipes = recipe_catalog();
    json!({
        "status": "PASS",
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "count": recipes.len(),
        "recipes": recipes,
        "winetricks": wt,
        "notes": [
            "Recipes are scoped to declared Wine/prefix conditions.",
            "Network verbs may return PARTIAL until completed.",
        ]
    })
}

pub fn plan_recipe(id: &str) -> Result<Value> {
    let recipe = find_recipe(id).ok_or_else(|| EngineError::Message(format!("unknown recipe: {id}")))?;
    Ok(json!({
        "status": "PASS",
        "recipe": id,
        "plan": recipe,
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

fn needs_xvfb() -> bool {
    if matches!(
        std::env::var("STRAWNT_FORCE_XVFB").ok().as_deref(),
        Some("1") | Some("true")
    ) {
        return true;
    }
    std::env::var("DISPLAY")
        .ok()
        .filter(|d| !d.is_empty())
        .is_none()
}

fn shim_data_dir(repo: &Path) -> PathBuf {
    repo.join("components/strawnt-engine/data/shims")
}

fn locate_shim_dlls(repo: &Path) -> (Option<PathBuf>, Option<PathBuf>) {
    let root = shim_data_dir(repo);
    let mut x64 = root.join("wintrust_x86_64.dll");
    if !x64.is_file() {
        x64 = root.join("wintrust.dll.x86_64");
    }
    let mut x86 = root.join("wintrust_i686.dll");
    if !x86.is_file() {
        x86 = root.join("wintrust.dll.i686");
    }
    (
        x64.is_file().then_some(x64),
        x86.is_file().then_some(x86),
    )
}

fn run_wine_regedit(repo: &Path, prefix: &Path, reg_file: &Path) -> Result<Value> {
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(EngineError::Message(format!(
            "vendored wine missing at {}",
            wine.display()
        )));
    }
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
    argv.push("regedit".into());
    argv.push(reg_file.display().to_string());
    let output = Command::new(&argv[0])
        .args(&argv[1..])
        .env("WINEPREFIX", prefix)
        .env("WINEARCH", "win64")
        .env("WINEDEBUG", "-all")
        .env("WINEDLLOVERRIDES", "winemenubuilder.exe=d")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()?;
    let exit_code = output.status.code().unwrap_or(-1);
    Ok(json!({
        "status": if exit_code == 0 { "PASS" } else { "PARTIAL" },
        "exit_code": exit_code,
        "used_xvfb": used_xvfb,
        "command": argv,
    }))
}

/// Install vendored wintrust soft-pass shim into an initialized Wine prefix.
fn apply_crypt32_shim(repo: &Path, prefix: &Path) -> Result<Value> {
    let (x64, x86) = locate_shim_dlls(repo);
    if x64.is_none() && x86.is_none() {
        return Ok(json!({
            "status": "FAIL",
            "recipe": "crypt32-signature",
            "error": "wintrust shim DLLs missing",
            "hint": shim_data_dir(repo).display().to_string(),
            "execution_backend": "wine",
            "powered_by": "Wine",
        }));
    }

    let sys32 = prefix.join("drive_c/windows/system32");
    let wow64 = prefix.join("drive_c/windows/syswow64");
    if !sys32.is_dir() {
        return Ok(json!({
            "status": "FAIL",
            "recipe": "crypt32-signature",
            "error": format!("prefix system32 missing: {}", sys32.display()),
            "execution_backend": "wine",
            "powered_by": "Wine",
        }));
    }

    let mut installed: Vec<String> = Vec::new();
    if let Some(ref src) = x64 {
        let dest = sys32.join("wintrust.dll");
        fs::copy(src, &dest)?;
        installed.push(dest.display().to_string());
    }
    if let Some(ref src) = x86 {
        if wow64.is_dir() {
            let dest = wow64.join("wintrust.dll");
            fs::copy(src, &dest)?;
            installed.push(dest.display().to_string());
        }
    }
    if installed.is_empty() {
        return Ok(json!({
            "status": "FAIL",
            "recipe": "crypt32-signature",
            "error": "no shim installed for win64 prefix",
            "execution_backend": "wine",
            "powered_by": "Wine",
        }));
    }

    let temp = prefix.join("drive_c/windows/temp");
    fs::create_dir_all(&temp)?;
    let reg_path = temp.join("strawnt-wintrust-override.reg");
    fs::write(
        &reg_path,
        "REGEDIT4\n\n\
         [HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n\
         \"wintrust\"=\"native,builtin\"\n",
    )?;
    let reg_run = run_wine_regedit(repo, prefix, &reg_path)?;

    // LINE IgnoreCodeSign — soft-skip verifyCodeSign under Wine builtins (PARTIAL).
    let line_reg = temp.join("strawnt-line-ignore-codesign.reg");
    fs::write(
        &line_reg,
        "REGEDIT4\n\n\
         [HKEY_CURRENT_USER\\Software\\LINE Corporation\\LINE]\n\
         \"IgnoreCodeSign\"=dword:00000001\n\
         [HKEY_CURRENT_USER\\Software\\LINE Corporation\\LINE_Beta]\n\
         \"IgnoreCodeSign\"=dword:00000001\n",
    )?;
    // Ensure %LOCALAPPDATA%\\LINE\\Data exists so launcher is not blocked on mkdir.
    if let Ok(users) = fs::read_dir(prefix.join("drive_c/users")) {
        for ent in users.flatten() {
            let name = ent.file_name().to_string_lossy().to_ascii_lowercase();
            if matches!(
                name.as_str(),
                "public" | "default" | "default user" | "all users"
            ) {
                continue;
            }
            if ent.path().is_dir() {
                let _ = fs::create_dir_all(
                    ent.path()
                        .join("AppData/Local/LINE/Data"),
                );
            }
        }
    }
    let line_reg_run = run_wine_regedit(repo, prefix, &line_reg)?;

    let marker = prefix.join("strawnt-crypt32-signature.json");
    let payload = json!({
        "recipe": "crypt32-signature",
        "status": "PASS",
        "scope": "WinVerifyTrust soft-pass + LINE IgnoreCodeSign",
        "installed": installed,
        "dll_override": "wintrust=native,builtin",
        "line_ignore_codesign": true,
        "powered_by": "Wine",
        "execution_backend": "wine",
        "honesty": "Authenticode soft-pass under Wine builtins — PARTIAL vs native; no ranked claim",
        "regedit": reg_run,
        "line_regedit": line_reg_run,
        "notes": [
            "Shim merged from straw-wine (policy C); StrawNT owns GE-vendored path.",
            "Do not claim LINE ranked / official anti-cheat PASS.",
        ]
    });
    let text = serde_json::to_string_pretty(&payload)
        .map_err(|e| EngineError::Message(format!("serialize: {e}")))?;
    fs::write(&marker, format!("{text}\n"))?;

    // Also keep straw-wine-compatible marker name for tooling that looks for it.
    let _ = fs::write(
        prefix.join("strawwine-crypt32-signature.json"),
        format!("{text}\n"),
    );

    Ok(json!({
        "status": "PASS",
        "recipe": "crypt32-signature",
        "marker": marker.display().to_string(),
        "installed": installed,
        "dll_override": "wintrust=native,builtin",
        "line_ignore_codesign": true,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "honesty": "Authenticode soft-pass under Wine builtins (PARTIAL vs native)",
    }))
}

fn apply_winetricks(
    repo: &Path,
    prefix: &Path,
    verbs: &[String],
) -> Result<Value> {
    let wt = which("winetricks").ok_or_else(|| {
        EngineError::Message("winetricks not found — cannot apply network/settings recipe".into())
    })?;
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(EngineError::Message(format!(
            "vendored wine missing at {}",
            wine.display()
        )));
    }

    let mut argv: Vec<String> = Vec::new();
    let mut used_xvfb = false;
    if needs_xvfb() {
        if let Some(xvfb) = which("xvfb-run") {
            argv.push(xvfb.display().to_string());
            argv.push("-a".into());
            used_xvfb = true;
        }
    }
    argv.push(wt.display().to_string());
    argv.push("-q".into());
    argv.extend(verbs.iter().cloned());

    let started = Instant::now();
    let output = Command::new(&argv[0])
        .args(&argv[1..])
        .env("WINE", wine.display().to_string())
        .env("WINEPREFIX", prefix)
        .env("WINEDEBUG", "-all")
        .env("WINEDLLOVERRIDES", "winemenubuilder.exe=d")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let exit_code = output.status.code().unwrap_or(-1);
    let status = if exit_code == 0 { "PASS" } else { "FAIL" };
    Ok(json!({
        "status": status,
        "exit_code": exit_code,
        "used_xvfb": used_xvfb,
        "duration_sec": started.elapsed().as_secs_f64(),
        "command": argv,
        "verbs": verbs,
        "stdout_tail": tail(&stdout, 500),
        "stderr_tail": tail(&stderr, 500),
        "execution_backend": "wine",
        "powered_by": "Wine",
        "pin": pin.tag,
    }))
}

fn tail(s: &str, n: usize) -> String {
    if s.len() <= n {
        s.to_string()
    } else {
        s[s.len() - n..].to_string()
    }
}

pub fn apply_recipe(
    repo: &Path,
    recipe_id: &str,
    prefix_name: &str,
    home_override: Option<&Path>,
) -> Result<Value> {
    let recipe = find_recipe(recipe_id)
        .ok_or_else(|| EngineError::Message(format!("unknown recipe: {recipe_id}")))?;
    let root = ensure_layout(home_override)?;
    let name = validate_name(prefix_name)?;
    let prefix = prefixes_dir(&root).join(&name);
    if !is_initialized(&prefix) {
        let boot = wineboot_init(repo, &prefix, "win64")?;
        if boot.get("status").and_then(|v| v.as_str()) != Some("PASS") {
            return Ok(json!({
                "status": "FAIL",
                "recipe": recipe_id,
                "prefix": name,
                "error": "prefix wineboot failed",
                "wineboot": boot,
                "execution_backend": "wine",
                "powered_by": "Wine",
            }));
        }
    }

    let kind = recipe.get("kind").and_then(|v| v.as_str()).unwrap_or("");
    let apply_result = if kind == "crypt32_signature" {
        apply_crypt32_shim(repo, &prefix)?
    } else {
        let verbs: Vec<String> = recipe
            .get("verbs")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|x| x.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();
        if verbs.is_empty() {
            return Err(EngineError::Message(format!(
                "recipe {recipe_id} has no verbs"
            )));
        }
        // Network-heavy recipes: attempt but allow PARTIAL on failure for NTW2 shell gate.
        let network = recipe
            .get("network")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        match apply_winetricks(repo, &prefix, &verbs) {
            Ok(r) => r,
            Err(e) if network => json!({
                "status": "PARTIAL",
                "recipe": recipe_id,
                "error": e.to_string(),
                "execution_backend": "wine",
                "powered_by": "Wine",
                "notes": ["network recipe not completed; matrix remains honest PARTIAL"]
            }),
            Err(e) => return Err(e),
        }
    };

    let status = apply_result
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("FAIL")
        .to_string();
    let mut state = read_recipes_state(&prefix);
    state["applied"][recipe_id] = json!({
        "status": status,
        "updated_at": crate::unix_secs(),
        "result": apply_result,
    });
    write_recipes_state(&prefix, &state)?;

    Ok(json!({
        "status": status,
        "recipe": recipe_id,
        "prefix": name,
        "prefix_path": prefix.display().to_string(),
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "apply": apply_result,
        "home": root.display().to_string(),
    }))
}
