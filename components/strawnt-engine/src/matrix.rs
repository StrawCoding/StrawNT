//! Compatibility matrix — honest PASS/PARTIAL/FAIL/UNKNOWN only.
//! Golden P0 seeds: line.exe + steam.exe (NTW2).

use serde_json::{json, Value};
use std::path::Path;

use crate::paths::{ensure_layout, read_matrix, write_matrix};
use crate::{EngineError, Result};

fn slug(name: &str) -> String {
    let s: String = name
        .trim()
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-' {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let s = s.trim_matches(|c| c == '-' || c == '.' || c == '_').to_string();
    if s.is_empty() {
        "app".into()
    } else {
        s.chars().take(80).collect()
    }
}

fn normalize(status: &str) -> String {
    match status.trim().to_ascii_uppercase().as_str() {
        "PASS" => "PASS".into(),
        "PARTIAL" => "PARTIAL".into(),
        "FAIL" => "FAIL".into(),
        _ => "UNKNOWN".into(),
    }
}

pub fn list_matrix(home_override: Option<&Path>) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let data = read_matrix(&root)?;
    let mut entries: Vec<Value> = data
        .get("entries")
        .and_then(|e| e.as_object())
        .map(|m| m.values().cloned().collect())
        .unwrap_or_default();
    let mut counts = json!({"PASS": 0, "PARTIAL": 0, "FAIL": 0, "UNKNOWN": 0});
    for e in &mut entries {
        let st = normalize(e.get("status").and_then(|v| v.as_str()).unwrap_or("UNKNOWN"));
        e["status"] = json!(st);
        let key = st.clone();
        let n = counts.get(&key).and_then(|v| v.as_i64()).unwrap_or(0);
        counts[key] = json!(n + 1);
    }
    entries.sort_by(|a, b| {
        let an = a.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let bn = b.get("name").and_then(|v| v.as_str()).unwrap_or("");
        an.to_ascii_lowercase()
            .cmp(&bn.to_ascii_lowercase())
    });
    Ok(json!({
        "status": "PASS",
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "count": entries.len(),
        "counts": counts,
        "entries": entries,
        "home": root.display().to_string(),
        "notes": [
            "Unknown software must stay UNKNOWN — never fake all-green.",
            "Statuses are scoped to declared Wine / prefix conditions.",
            "line.exe / steam.exe golden rows are PARTIAL until install+visible UI proven.",
        ]
    }))
}

pub fn get_entry(app_key: &str, home_override: Option<&Path>) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let data = read_matrix(&root)?;
    let key = slug(app_key);
    match data
        .get("entries")
        .and_then(|e| e.get(&key))
        .cloned()
    {
        Some(mut entry) => {
            let st = normalize(entry.get("status").and_then(|v| v.as_str()).unwrap_or("UNKNOWN"));
            entry["status"] = json!(st);
            entry["found"] = json!(true);
            entry["execution_backend"] = json!("wine");
            entry["powered_by"] = json!("Wine");
            Ok(entry)
        }
        None => Ok(json!({
            "status": "UNKNOWN",
            "execution_backend": "wine",
            "powered_by": "Wine",
            "app_key": key,
            "found": false,
            "message": "No matrix entry — treat as UNKNOWN until verified.",
        })),
    }
}

pub fn set_entry(
    name: &str,
    status: &str,
    notes: &str,
    prefix: Option<&str>,
    app_key: Option<&str>,
    extra: Option<Value>,
    home_override: Option<&Path>,
) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let st = normalize(status);
    let key = slug(app_key.unwrap_or(name));
    let mut data = read_matrix(&root)?;
    let now = crate::unix_secs();
    let mut entry = json!({
        "app_key": key,
        "name": name,
        "status": st,
        "notes": notes,
        "prefix": prefix,
        "wine_flavor": "proton-ge",
        "engine": "proton-ge",
        "execution_backend": "wine",
        "backend": "wine",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "updated_at": now,
    });
    if let Some(ex) = extra {
        if let Some(obj) = ex.as_object() {
            for (k, v) in obj {
                entry[k] = v.clone();
            }
        }
    }
    data["entries"][&key] = entry.clone();
    write_matrix(&root, &data)?;
    Ok(json!({
        "status": "PASS",
        "execution_backend": "wine",
        "powered_by": "Wine",
        "entry": entry,
        "home": root.display().to_string(),
    }))
}

/// Seed golden P0 matrix rows for line.exe + steam.exe (honest PARTIAL).
pub fn seed_golden(home_override: Option<&Path>, pin: &str) -> Result<Value> {
    let root = ensure_layout(home_override)?;
    let line = set_entry(
        "line.exe",
        "PARTIAL",
        "NTW2 shell seed: install/launch UI scope; IgnoreCodeSign/crypt32 path; not full LINE verification; no ranked claim",
        Some("line"),
        Some("line.exe"),
        Some(json!({
            "app": "line",
            "exe": "line.exe",
            "scopes": {
                "install": "PARTIAL",
                "launch": "PARTIAL",
                "visible_ui": "UNKNOWN",
                "login": "UNKNOWN"
            },
            "engine_pin": pin,
            "recipes_recommended": ["crypt32-signature", "vcrun", "corefonts"],
            "honesty": {
                "full_windows_claimed": false,
                "ranked_anticheat_claimed": false,
                "all_features_claimed": false
            }
        })),
        Some(&root),
    )?;
    let steam = set_entry(
        "steam.exe",
        "PARTIAL",
        "NTW2 shell seed: launcher start/login UI only; not all-games-play claim",
        Some("steam"),
        Some("steam.exe"),
        Some(json!({
            "app": "steam",
            "exe": "steam.exe",
            "scopes": {
                "install": "PARTIAL",
                "launch": "PARTIAL",
                "visible_ui": "UNKNOWN",
                "login": "UNKNOWN",
                "all_games": "UNKNOWN"
            },
            "engine_pin": pin,
            "recipes_recommended": ["vcrun", "corefonts", "dxvk"],
            "honesty": {
                "full_windows_claimed": false,
                "ranked_anticheat_claimed": false,
                "all_games_playable_claimed": false
            }
        })),
        Some(&root),
    )?;
    let listed = list_matrix(Some(&root))?;
    Ok(json!({
        "status": "PASS",
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "pin": pin,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "seeded": {
            "line": line.get("entry").cloned().unwrap_or(json!(null)),
            "steam": steam.get("entry").cloned().unwrap_or(json!(null)),
        },
        "matrix": listed,
        "home": root.display().to_string(),
    }))
}

pub fn export_golden_summary(home_override: Option<&Path>) -> Result<Value> {
    let listed = list_matrix(home_override)?;
    let entries = listed
        .get("entries")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let find = |key: &str| -> Option<Value> {
        entries.iter().find(|e| {
            e.get("app_key").and_then(|v| v.as_str()) == Some(key)
                || e.get("exe").and_then(|v| v.as_str()) == Some(key)
                || e.get("name").and_then(|v| v.as_str()) == Some(key)
        }).cloned()
    };
    let line = find("line.exe").ok_or_else(|| EngineError::Message("line.exe matrix row missing".into()))?;
    let steam = find("steam.exe").ok_or_else(|| EngineError::Message("steam.exe matrix row missing".into()))?;
    Ok(json!({
        "line": line,
        "steam": steam,
        "list": listed,
    }))
}
