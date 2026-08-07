//! NTW5 App Manager smoke — exercises locked capabilities end-to-end.

use crate::{
    app_compat, app_prefix, app_recipes, get_channel, grant_permission, install_catalog,
    launch_app, list_apps, list_catalog, list_permissions, list_sysapps, set_channel, status,
    uninstall_app, AppMgrError,
};
use serde_json::{json, Value};
use std::path::Path;

pub fn run_appmgr_smoke(home: Option<&Path>) -> Result<Value, AppMgrError> {
    let mut notes = vec![
        "NTW5 system App Manager smoke".into(),
        "powered by Wine — not a full Windows / ranked anti-cheat claim".into(),
    ];
    let mut failures: Vec<String> = Vec::new();

    let st = status(home)?;
    let catalog = list_catalog()?;
    let sysapps = list_sysapps(home)?;
    let ch0 = get_channel(home)?;
    let ch1 = set_channel("beta", home)?;
    let _ch2 = set_channel("stable", home)?;

    let line = match install_catalog("line", None, home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("install line: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };
    let steam = match install_catalog("steam", None, home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("install steam: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };

    let listed = list_apps(home)?;
    let has_line = listed
        .get("apps")
        .and_then(|a| a.as_array())
        .map(|arr| arr.iter().any(|x| x.get("id").and_then(|v| v.as_str()) == Some("line")))
        .unwrap_or(false);
    let has_steam = listed
        .get("apps")
        .and_then(|a| a.as_array())
        .map(|arr| {
            arr.iter()
                .any(|x| x.get("id").and_then(|v| v.as_str()) == Some("steam"))
        })
        .unwrap_or(false);
    if !has_line {
        failures.push("list missing line after install".into());
    }
    if !has_steam {
        failures.push("list missing steam after install".into());
    }

    let prefix = match app_prefix("line", Some("line"), home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("prefix: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };

    let recipes = match app_recipes("line", Some("crypt32-signature"), home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("recipes: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };

    let perms = match grant_permission("line", "interop.cross_prefix", home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("permissions: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };
    let perms_list = list_permissions(Some("line"), home)?;

    let compat = match app_compat("line", home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("compat: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };

    let launch = match launch_app("line", home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("launch: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };
    if launch.get("status").and_then(|v| v.as_str()) != Some("PASS") {
        failures.push(format!(
            "launch status={}",
            launch.get("status").and_then(|v| v.as_str()).unwrap_or("?")
        ));
    }
    if launch.get("mode").and_then(|v| v.as_str()) != Some("pe") {
        failures.push(format!(
            "launch mode={} (require pe — not cmd_marker)",
            launch.get("mode").and_then(|v| v.as_str()).unwrap_or("?")
        ));
    }
    if launch
        .get("honesty")
        .and_then(|h| h.get("simulated"))
        .and_then(|v| v.as_bool())
        == Some(true)
    {
        failures.push("launch honesty.simulated=true refused for NTW5 PASS".into());
    }

    // Uninstall a disposable catalog copy is ok for steam after list/launch proven.
    let uninstall = match uninstall_app("steam", home) {
        Ok(v) => v,
        Err(e) => {
            failures.push(format!("uninstall: {e}"));
            json!({"status": "FAIL", "error": e.to_string()})
        }
    };

    let sys_count = sysapps.get("count").and_then(|v| v.as_u64()).unwrap_or(0);
    if sys_count < 7 {
        failures.push(format!("sysapps count {sys_count} < 7"));
    }

    let line_pe = line.get("install_mode").and_then(|v| v.as_str()) == Some("pe_staged")
        && line
            .get("staged_pe")
            .and_then(|v| v.as_str())
            .map(|p| Path::new(p).is_file())
            .unwrap_or(false);
    let steam_pe = steam.get("install_mode").and_then(|v| v.as_str()) == Some("pe_staged")
        && steam
            .get("staged_pe")
            .and_then(|v| v.as_str())
            .map(|p| Path::new(p).is_file())
            .unwrap_or(false);
    if !line_pe {
        failures.push("install line missing pe_staged PE file".into());
    }
    if !steam_pe {
        failures.push("install steam missing pe_staged PE file".into());
    }

    let install_ok = line.get("status").and_then(|v| v.as_str()) == Some("PASS")
        && steam.get("status").and_then(|v| v.as_str()) == Some("PASS")
        && line_pe
        && steam_pe;
    let list_launch_ok = has_line
        && launch.get("status").and_then(|v| v.as_str()) == Some("PASS")
        && launch.get("mode").and_then(|v| v.as_str()) == Some("pe");
    let prefix_ok = prefix.get("status").and_then(|v| v.as_str()) == Some("PASS");

    let capabilities = json!({
        "install": install_ok,
        "uninstall": uninstall.get("status").and_then(|v| v.as_str()) == Some("PASS"),
        "list_launch": list_launch_ok,
        "prefix": prefix_ok,
        "deps_recipes": recipes.get("status").and_then(|v| v.as_str()) == Some("PASS")
            || recipes.get("status").and_then(|v| v.as_str()) == Some("PARTIAL"),
        "update_channel": ch1.get("status").and_then(|v| v.as_str()) == Some("PASS"),
        "permissions": perms.get("status").and_then(|v| v.as_str()) == Some("PASS"),
        "telemetry_compat": compat.get("status").and_then(|v| v.as_str()) == Some("PASS"),
        "store_catalog": catalog.get("status").and_then(|v| v.as_str()) == Some("PASS"),
        "dedicated_system_apps": sys_count >= 7,
    });

    let claims = json!({
        "install": install_ok,
        "list_launch": list_launch_ok,
        "prefix": prefix_ok,
        "full_windows_claimed": false,
        "ranked_anticheat_claimed": false,
        "powered_by_wine": true,
        "simulated": false,
    });

    if !install_ok {
        failures.push("capability install false".into());
    }
    if !list_launch_ok {
        failures.push("capability list_launch false".into());
    }
    if !prefix_ok {
        failures.push("capability prefix false".into());
    }

    let status_str = if failures.is_empty() {
        "PASS"
    } else {
        notes.push(format!("failures: {}", failures.join("; ")));
        "FAIL"
    };

    let pin = st
        .get("engine")
        .cloned()
        .unwrap_or(json!("proton-ge"));

    Ok(json!({
        "schema": "strawnt-ntw5-appmgr/v1",
        "stage": "ntw5-app-manager",
        "status": status_str,
        "product": "StrawNT",
        "backend": "wine",
        "execution_backend": "wine",
        "engine": "proton-ge",
        "powered_by": "Wine",
        "powered_by_wine": true,
        "simulated": false,
        "capabilities": capabilities,
        "claims": claims,
        "results": {
            "status": st,
            "catalog": catalog,
            "sysapps": sysapps,
            "channel_before": ch0,
            "channel_set": ch1,
            "install_line": line,
            "install_steam": steam,
            "list": listed,
            "prefix": prefix,
            "recipes": recipes,
            "permissions_grant": perms,
            "permissions_list": perms_list,
            "compat": compat,
            "launch": launch,
            "uninstall_steam": uninstall,
        },
        "failures": failures,
        "notes": notes,
        "engine_label": pin,
    }))
}
