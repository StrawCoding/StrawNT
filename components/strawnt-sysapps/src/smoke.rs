//! NTW6 dedicated system apps smoke — 7 roles, each with manifest+launch+side effect.

use crate::launch::launch_role;
use crate::roles::{DedicatedRole, DEDICATED_ROLES, SYSAPP_COUNT};
use crate::{list_apps, load_manifest, Result};
use serde_json::{json, Value};
use std::path::Path;

pub fn run_sysapps_smoke(home: Option<&Path>) -> Result<Value> {
    let mut notes = vec![
        "NTW6 dedicated system apps smoke".into(),
        "powered by Wine — not a full Windows / ranked anti-cheat claim".into(),
        "Hub = Electron; thin vertical slices only".into(),
    ];
    let mut failures: Vec<String> = Vec::new();
    let mut apps: Vec<Value> = Vec::new();
    let mut results: Vec<Value> = Vec::new();

    let listed = list_apps(home)?;
    let list_count = listed.get("count").and_then(|v| v.as_u64()).unwrap_or(0);
    if list_count < SYSAPP_COUNT as u64 {
        failures.push(format!("sysapps list count {list_count} < {SYSAPP_COUNT}"));
    }

    for role in DEDICATED_ROLES {
        let manifest = match load_manifest(*role) {
            Ok(v) => v,
            Err(e) => {
                failures.push(format!("{} manifest: {e}", role.as_str()));
                json!({"status": "FAIL", "error": e.to_string(), "role": role.as_str()})
            }
        };
        let manifest_ok = manifest.get("schema").and_then(|v| v.as_str())
            == Some("strawnt-app-manifest/v1")
            && manifest
                .get("dedicated_role")
                .and_then(|v| v.as_str())
                == Some(role.as_str());
        if !manifest_ok {
            failures.push(format!("{} manifest schema/role mismatch", role.as_str()));
        }

        let arg = match role {
            DedicatedRole::RunDialog => Some("cmd /c echo STRAWNT_RUN_DIALOG_OK"),
            DedicatedRole::InstallerWizard => Some("line"),
            _ => None,
        };
        let launch = match launch_role(*role, home, arg) {
            Ok(v) => v,
            Err(e) => {
                failures.push(format!("{} launch: {e}", role.as_str()));
                json!({"status": "FAIL", "error": e.to_string(), "role": role.as_str()})
            }
        };
        let launch_status = launch.get("status").and_then(|v| v.as_str()).unwrap_or("?");
        if launch_status != "PASS" && launch_status != "PARTIAL" {
            failures.push(format!("{} launch status={launch_status}", role.as_str()));
        }
        if launch
            .get("honesty")
            .and_then(|h| h.get("simulated"))
            .and_then(|v| v.as_bool())
            == Some(true)
        {
            failures.push(format!("{} honesty.simulated=true refused", role.as_str()));
        }
        let se = launch
            .get("side_effect")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if se.is_empty() || !Path::new(se).is_file() {
            failures.push(format!("{} missing side_effect file", role.as_str()));
        }

        // Desktop + hub tab from list row.
        let row = listed
            .get("apps")
            .and_then(|a| a.as_array())
            .and_then(|arr| {
                arr.iter()
                    .find(|x| x.get("role").and_then(|r| r.as_str()) == Some(role.as_str()))
            })
            .cloned()
            .unwrap_or(json!({}));
        if row.get("manifest_present").and_then(|v| v.as_bool()) != Some(true) {
            failures.push(format!("{} manifest_present=false", role.as_str()));
        }
        if row.get("desktop_present").and_then(|v| v.as_bool()) != Some(true) {
            failures.push(format!("{} desktop_present=false", role.as_str()));
        }

        let app_row = json!({
            "id": role.app_id(),
            "role": role.as_str(),
            "name": role.display_name(),
            "status": if launch_status == "PASS" || launch_status == "PARTIAL" { "PASS" } else { "FAIL" },
            "manifest_ok": manifest_ok,
            "launch_status": launch_status,
            "side_effect": se,
            "hub_tab": role.hub_tab(),
            "desktop": row.get("desktop"),
            "manifest": row.get("manifest"),
        });
        apps.push(app_row);
        results.push(json!({
            "role": role.as_str(),
            "manifest": manifest,
            "launch": launch,
            "list_row": row,
        }));
    }

    let pass_count = apps
        .iter()
        .filter(|a| a.get("status").and_then(|v| v.as_str()) == Some("PASS"))
        .count();
    if pass_count < SYSAPP_COUNT {
        failures.push(format!("PASS apps {pass_count} < {SYSAPP_COUNT}"));
    }

    let status_str = if failures.is_empty() {
        "PASS"
    } else {
        notes.push(format!("failures: {}", failures.join("; ")));
        "FAIL"
    };

    let repo = strawnt_engine::find_repo_root().ok();
    let pin = repo
        .as_ref()
        .and_then(|r| strawnt_engine::load_pin(r).ok())
        .map(|p| p.tag)
        .unwrap_or_else(|| "unknown".into());

    Ok(json!({
        "schema": "strawnt-ntw6-sysapps/v1",
        "stage": "ntw6-sysapps",
        "status": status_str,
        "product": "StrawNT",
        "backend": "wine",
        "execution_backend": "wine",
        "engine": "proton-ge",
        "engine_pin": pin,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "simulated": false,
        "hub": "electron",
        "apps": apps,
        "results": results,
        "list": listed,
        "claims": {
            "app_count": apps.len(),
            "dedicated_system_apps": apps.len() >= SYSAPP_COUNT,
            "powered_by_wine": true,
            "full_windows_claimed": false,
            "ranked_anticheat_claimed": false,
            "simulated": false,
            "hub_electron": true,
        },
        "failures": failures,
        "notes": notes,
    }))
}
