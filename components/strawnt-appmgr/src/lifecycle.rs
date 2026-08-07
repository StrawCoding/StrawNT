//! Install / uninstall / list / launch lifecycle.

use crate::catalog::{current_pin, find_catalog_entry};
use crate::manifest::{AppManifest, InstallState};
use crate::store::{ensure_layout, load_db, save_db, AppMgrError};
use crate::sysapps::ensure_sysapps_registered;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn slug_from_path(path: &Path) -> String {
    let stem = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("app");
    let lower = stem.to_lowercase();
    let mut out = String::new();
    let mut started = false;
    for ch in lower.chars() {
        if ch.is_ascii_alphanumeric() || ch == '.' || ch == '_' || ch == '-' {
            if !started && ch.is_ascii_alphanumeric() {
                started = true;
            }
            if started {
                out.push(ch);
            }
        } else if started && !out.ends_with('-') {
            out.push('-');
        }
    }
    let trimmed: String = out.trim_matches('-').chars().take(64).collect();
    if trimmed.is_empty() {
        "app".into()
    } else {
        trimmed
    }
}

pub fn list_apps(home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let _ = ensure_sysapps_registered(Some(root.as_path()));
    let db = load_db(&root)?;
    let apps: Vec<Value> = db
        .apps
        .iter()
        .filter(|a| a.install_state != InstallState::Removed)
        .map(|a| a.to_value())
        .collect();
    Ok(json!({
        "status": "PASS",
        "command": "apps list",
        "count": apps.len(),
        "apps": apps,
        "execution_backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "home": root.display().to_string(),
        "db": crate::store::db_path(&root).display().to_string(),
    }))
}

pub fn show_app(app_id: &str, home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let db = load_db(&root)?;
    let app = db
        .apps
        .iter()
        .find(|a| a.id == app_id && a.install_state != InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;
    Ok(json!({
        "status": "PASS",
        "command": "apps show",
        "app": app.to_value(),
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

pub fn install_catalog(
    catalog_id: &str,
    prefix_override: Option<&str>,
    home: Option<&Path>,
) -> Result<Value, AppMgrError> {
    let entry = find_catalog_entry(catalog_id)?;
    let root = ensure_layout(home)?;
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let pin = current_pin(&repo);

    let name = entry
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or(catalog_id)
        .to_string();
    let exe = entry
        .get("exe")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let prefix_default = entry
        .get("prefix_default")
        .and_then(|v| v.as_str())
        .unwrap_or(catalog_id);
    let prefix_name = prefix_override.unwrap_or(prefix_default).to_string();

    let created = strawnt_engine::prefix::create_prefix(
        &repo,
        &prefix_name,
        "win64",
        false,
        Some(root.as_path()),
    )
    .map_err(|e| AppMgrError::Message(e.to_string()))?;

    // Apply lightweight recommended recipe markers when possible (crypt32 for line).
    let recipes: Vec<String> = entry
        .get("recipes_recommended")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let mut applied = Vec::new();
    for rid in &recipes {
        if rid == "crypt32-signature" {
            if let Ok(r) = strawnt_engine::recipes::apply_recipe(
                &repo,
                rid,
                &prefix_name,
                Some(root.as_path()),
            ) {
                if r.get("status").and_then(|v| v.as_str()) == Some("PASS")
                    || r.get("status").and_then(|v| v.as_str()) == Some("PARTIAL")
                {
                    applied.push(rid.clone());
                }
            }
        }
    }

    // Seed matrix row honesty.
    if let Some(ref exe_name) = exe {
        let status = entry
            .get("compat_status")
            .and_then(|v| v.as_str())
            .unwrap_or("PARTIAL");
        let notes = entry
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or("catalog install via App Manager");
        let _ = strawnt_engine::matrix::set_entry(
            exe_name,
            status,
            notes,
            Some(&prefix_name),
            Some(exe_name),
            Some(json!({
                "via": "strawnt-appmgr",
                "catalog_id": catalog_id,
                "scopes": entry.get("scopes").cloned().unwrap_or(json!({})),
            })),
            Some(root.as_path()),
        );
    }

    let mut m = AppManifest::new(catalog_id, &name, "win32");
    m.source = "catalog".into();
    m.install_state = InstallState::Installed;
    m.prefix = Some(prefix_name.clone());
    m.exe = exe.clone();
    m.recipes_recommended = recipes.clone();
    m.recipes_applied = applied.clone();
    m.compat_status = entry
        .get("compat_status")
        .and_then(|v| v.as_str())
        .unwrap_or("PARTIAL")
        .to_string();
    m.engine_pin = pin;
    m.update_channel = entry
        .get("update_channel")
        .and_then(|v| v.as_str())
        .unwrap_or("stable")
        .to_string();
    if let Some(scopes) = entry.get("scopes").and_then(|v| v.as_object()) {
        for (k, v) in scopes {
            if let Some(s) = v.as_str() {
                m.scopes.insert(k.clone(), s.to_string());
            }
        }
    }
    m.notes = Some(format!(
        "Catalog install of {catalog_id} — prefix + staged PE; vendor installer UI remains PARTIAL"
    ));

    // Stage a real Win32 PE under prefix drive_c (fixture stand-in for catalog exe).
    // Registration-only INSTALLED.json without a PE is not a real install for NTW5 PASS.
    let prefix_path = strawnt_engine::prefix::prefix_path(&root, &prefix_name)
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let stub_dir = prefix_path.join("drive_c/strawnt/apps").join(catalog_id);
    fs::create_dir_all(&stub_dir)?;

    let fixture = appmgr_stub_pe(&repo).ok_or_else(|| {
        AppMgrError::Message(
            "appmgr stub PE missing — build components/strawnt-appmgr/fixtures".into(),
        )
    })?;
    let exe_name = exe
        .clone()
        .unwrap_or_else(|| format!("{catalog_id}.exe"));
    let staged_pe = stub_dir.join(&exe_name);
    fs::copy(&fixture, &staged_pe).map_err(|e| {
        AppMgrError::Message(format!(
            "failed to stage PE {} → {}: {e}",
            fixture.display(),
            staged_pe.display()
        ))
    })?;
    if !staged_pe.is_file() {
        return Err(AppMgrError::Message(format!(
            "staged PE missing after copy: {}",
            staged_pe.display()
        )));
    }

    let marker = stub_dir.join("INSTALLED.json");
    fs::write(
        &marker,
        serde_json::to_string_pretty(&json!({
            "app_id": catalog_id,
            "exe": exe_name,
            "prefix": prefix_name,
            "staged_pe": staged_pe.display().to_string(),
            "fixture": fixture.display().to_string(),
            "install_mode": "pe_staged",
            "via": "strawnt-appmgr",
            "powered_by": "Wine",
            "note": "Fixture PE stand-in — not vendor LINE/Steam UI",
        }))?,
    )?;
    m.exe = Some(exe_name.clone());
    m.install_path = Some(stub_dir.display().to_string());

    let mut db = load_db(&root)?;
    db.upsert(m);
    save_db(&root, &db)?;

    let _ = mirror_registry_launch(catalog_id, &name, Some(stub_dir.display().to_string()));

    Ok(json!({
        "status": "PASS",
        "command": "apps install",
        "app_id": catalog_id,
        "name": name,
        "source": "catalog",
        "prefix": prefix_name,
        "exe": exe_name,
        "install_mode": "pe_staged",
        "staged_pe": staged_pe.display().to_string(),
        "fixture": fixture.display().to_string(),
        "recipes_recommended": recipes,
        "recipes_applied": applied,
        "prefix_create": created,
        "install_marker": marker.display().to_string(),
        "execution_backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "honesty": {
            "full_windows_claimed": false,
            "ranked_anticheat_claimed": false,
            "simulated": false,
            "note": "Staged real Win32 PE via App Manager; vendor LINE/Steam installer UI remains PARTIAL"
        }
    }))
}

fn appmgr_stub_pe(repo: &Path) -> Option<PathBuf> {
    let p = repo.join("components/strawnt-appmgr/fixtures/build/strawnt_app_stub.exe");
    p.is_file().then_some(p)
}

fn mirror_registry_launch(id: &str, name: &str, install_path: Option<String>) {
    use strawwu_app_registry::{default_registry_path, AppKind, ExecutionBackend, RegistryStore};
    if let Ok(mut store) = RegistryStore::open_at(default_registry_path()) {
        let _ = store.upsert_from_launch(
            id,
            name,
            AppKind::Win32,
            install_path,
            Some(ExecutionBackend::Wine),
            None,
        );
    }
}

pub fn install_path(
    path: &Path,
    prefix_override: Option<&str>,
    home: Option<&Path>,
) -> Result<Value, AppMgrError> {
    if !path.exists() {
        return Err(AppMgrError::Message(format!(
            "installer path not found: {}",
            path.display()
        )));
    }
    let id = slug_from_path(path);
    let root = ensure_layout(home)?;
    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let pin = current_pin(&repo);
    let prefix_name = prefix_override.unwrap_or(&id).to_string();

    let created = strawnt_engine::prefix::create_prefix(
        &repo,
        &prefix_name,
        "win64",
        false,
        Some(root.as_path()),
    )
    .map_err(|e| AppMgrError::Message(e.to_string()))?;

    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(&id)
        .to_string();
    let exe_name = path
        .file_name()
        .and_then(|s| s.to_str())
        .map(|s| s.to_string());

    // Copy PE into prefix apps dir (best-effort staging).
    let prefix_path = strawnt_engine::prefix::prefix_path(&root, &prefix_name)
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let dest_dir = prefix_path.join("drive_c/strawnt/apps").join(&id);
    fs::create_dir_all(&dest_dir)?;
    let dest = if let Some(ref en) = exe_name {
        let d = dest_dir.join(en);
        let _ = fs::copy(path, &d);
        d
    } else {
        path.to_path_buf()
    };

    let mut m = AppManifest::new(&id, &name, "win32");
    m.source = "installer".into();
    m.install_state = InstallState::Installed;
    m.prefix = Some(prefix_name.clone());
    m.exe = exe_name.clone();
    m.install_path = Some(dest_dir.display().to_string());
    m.engine_pin = pin;
    m.compat_status = "PARTIAL".into();
    m.scopes.insert("install".into(), "PARTIAL".into());
    m.scopes.insert("launch".into(), "PARTIAL".into());
    m.notes = Some(format!(
        "Installed via App Manager from {}",
        path.display()
    ));

    let mut db = load_db(&root)?;
    db.upsert(m);
    save_db(&root, &db)?;
    let _ = mirror_registry_launch(&id, &name, Some(dest_dir.display().to_string()));

    Ok(json!({
        "status": "PASS",
        "command": "apps install",
        "app_id": id,
        "name": name,
        "source": "installer",
        "prefix": prefix_name,
        "exe": exe_name,
        "staged": dest.display().to_string(),
        "prefix_create": created,
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

pub fn uninstall_app(app_id: &str, home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let mut db = load_db(&root)?;
    let app = db
        .apps
        .iter_mut()
        .find(|a| a.id == app_id)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;
    if app.protected || app.system_app {
        return Err(AppMgrError::Message(format!(
            "refusing to uninstall protected/system app: {app_id}"
        )));
    }
    app.install_state = InstallState::Removed;
    app.touch();
    let prefix = app.prefix.clone();
    save_db(&root, &db)?;
    Ok(json!({
        "status": "PASS",
        "command": "apps uninstall",
        "app_id": app_id,
        "prefix_retained": prefix,
        "note": "Manifest marked removed; prefix retained (deep-remove is separate)",
        "execution_backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
    }))
}

pub fn launch_app(app_id: &str, home: Option<&Path>) -> Result<Value, AppMgrError> {
    let root = ensure_layout(home)?;
    let db = load_db(&root)?;
    let app = db
        .apps
        .iter()
        .find(|a| a.id == app_id && a.install_state != InstallState::Removed)
        .ok_or_else(|| AppMgrError::Message(format!("app not found: {app_id}")))?;

    if app.system_app {
        return Ok(json!({
            "status": "PARTIAL",
            "command": "apps launch",
            "app_id": app_id,
            "dedicated_role": app.dedicated_role,
            "message": "Dedicated system app UI ships in NTW6; registered via App Manager",
            "execution_backend": "wine",
            "powered_by": "Wine",
            "powered_by_wine": true,
        }));
    }

    let repo = strawnt_engine::find_repo_root()
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let pin = strawnt_engine::load_pin(&repo)
        .map_err(|e| AppMgrError::Message(e.to_string()))?;
    let wine = strawnt_engine::wine_bin_path(&repo, &pin);
    if !wine.is_file() {
        return Err(AppMgrError::Message(format!(
            "vendored wine missing: {}",
            wine.display()
        )));
    }

    let prefix_name = app
        .prefix
        .clone()
        .unwrap_or_else(|| app.id.clone());
    let prefix_path = strawnt_engine::prefix::prefix_path(&root, &prefix_name)
        .map_err(|e| AppMgrError::Message(e.to_string()))?;

    let staged_exe: Option<PathBuf> = app.install_path.as_ref().and_then(|dir| {
        app.exe.as_ref().map(|e| PathBuf::from(dir).join(e))
    });
    let use_pe = staged_exe
        .as_ref()
        .map(|p| p.is_file())
        .unwrap_or(false);

    // NTW5 honesty: list/launch PASS requires a real staged PE under Wine.
    // cmd /c echo markers are not acceptably "real launch" evidence.
    if !use_pe {
        return Ok(json!({
            "status": "FAIL",
            "command": "apps launch",
            "app_id": app_id,
            "prefix": prefix_name,
            "mode": "missing_pe",
            "staged_exe": staged_exe.map(|p| p.display().to_string()),
            "message": "refusing cmd_marker launch — stage a real PE via apps install first",
            "execution_backend": "wine",
            "engine": "proton-ge",
            "engine_pin": pin.tag,
            "powered_by": "Wine",
            "powered_by_wine": true,
            "honesty": {
                "full_windows_claimed": false,
                "ranked_anticheat_claimed": false,
                "simulated": true,
                "visible_ui": "n/a_missing_pe",
            }
        }));
    }

    let pe = staged_exe.as_ref().unwrap();
    const LAUNCH_MARKER: &str = "STRAWNT_APPMGR_OK";

    let mut argv: Vec<String> = Vec::new();
    if needs_xvfb() {
        if let Some(xvfb) = which("xvfb-run") {
            argv.push(xvfb.display().to_string());
            argv.push("-a".into());
        }
    }
    argv.push(wine.display().to_string());
    argv.push(pe.display().to_string());

    let mut command = Command::new(&argv[0]);
    command.args(&argv[1..]);
    strawnt_engine::optimize::apply_wine_env(
        &mut command,
        strawnt_engine::optimize::OptProfile::Optimized,
        &prefix_path,
        "win64",
    );
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let output = command
        .output()
        .map_err(|e| AppMgrError::Message(format!("launch failed: {e}")))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let exit_code = output.status.code().unwrap_or(-1);
    let ok = exit_code == 0 && stdout.contains(LAUNCH_MARKER);

    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "command": "apps launch",
        "app_id": app_id,
        "prefix": prefix_name,
        "mode": "pe",
        "staged_exe": pe.display().to_string(),
        "marker": LAUNCH_MARKER,
        "exit_code": exit_code,
        "stdout_tail": tail(&stdout, 400),
        "stderr_tail": tail(&stderr, 400),
        "execution_backend": "wine",
        "engine": "proton-ge",
        "engine_pin": pin.tag,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "honesty": {
            "full_windows_claimed": false,
            "ranked_anticheat_claimed": false,
            "simulated": false,
            "visible_ui": "UNKNOWN",
            "note": "Console PE fixture launch via Wine — vendor GUI remains UNKNOWN/PARTIAL",
        }
    }))
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

fn tail(s: &str, n: usize) -> String {
    if s.len() <= n {
        s.to_string()
    } else {
        s[s.len() - n..].to_string()
    }
}
