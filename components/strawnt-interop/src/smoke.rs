//! NTW4 interop smoke: same_prefix named pipe + cross_prefix host broker.

use serde_json::{json, Value};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use strawnt_engine::optimize::{apply_wine_env, clone_prefix_from_template, ensure_template, OptProfile};
use strawnt_engine::paths::{ensure_layout, prefixes_dir};
use strawnt_engine::prefix::is_initialized;
use strawnt_engine::{find_repo_root, load_pin, wine_bin_path, EngineError};

use crate::broker::{BrokerConfig, BrokerHandle, Grant};

const SAME_PAYLOAD: &str = "STRAWNT_NTW4_SAME";
const CROSS_PAYLOAD: &str = "STRAWNT_NTW4_CROSS";
const PIPE_NAME: &str = "strawnt-ntw4-same";

#[derive(Debug, thiserror::Error)]
pub enum SmokeError {
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    Engine(#[from] EngineError),
    #[error(transparent)]
    Broker(#[from] crate::broker::BrokerError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, SmokeError>;

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn which(bin: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).find_map(|dir| {
            let p = dir.join(bin);
            p.is_file().then_some(p)
        })
    })
}

fn needs_xvfb() -> bool {
    if env_truthy("STRAWNT_FORCE_XVFB") {
        return true;
    }
    if env_truthy("STRAWNT_NO_XVFB") {
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

fn fixture_dir(repo: &Path) -> PathBuf {
    repo.join("components/strawnt-interop/fixtures")
}

fn fixture_build_dir(repo: &Path) -> PathBuf {
    fixture_dir(repo).join("build")
}

/// Build MinGW PE fixtures if missing.
pub fn ensure_fixtures(repo: &Path) -> Result<(PathBuf, PathBuf)> {
    let src_dir = fixture_dir(repo);
    let out_dir = fixture_build_dir(repo);
    fs::create_dir_all(&out_dir)?;
    let ac = out_dir.join("strawnt_ac_stub.exe");
    let game = out_dir.join("strawnt_game_stub.exe");
    let cc = which("x86_64-w64-mingw32-gcc").ok_or_else(|| {
        SmokeError::Message("x86_64-w64-mingw32-gcc required to build NTW4 PE fixtures".into())
    })?;

    let build_one = |src: &str, dest: &Path| -> Result<()> {
        let src_path = src_dir.join(src);
        if !src_path.is_file() {
            return Err(SmokeError::Message(format!(
                "fixture source missing: {}",
                src_path.display()
            )));
        }
        let need = !dest.is_file()
            || fs::metadata(&src_path)?.modified()? > fs::metadata(dest)?.modified()?;
        if !need {
            return Ok(());
        }
        let status = Command::new(&cc)
            .args([
                "-O2",
                "-s",
                "-o",
            ])
            .arg(dest)
            .arg(&src_path)
            .args(["-lws2_32"])
            .status()?;
        if !status.success() {
            return Err(SmokeError::Message(format!(
                "mingw build failed for {src}"
            )));
        }
        Ok(())
    };

    build_one("strawnt_ac_stub.c", &ac)?;
    build_one("strawnt_game_stub.c", &game)?;
    Ok((ac, game))
}

fn make_prefix(repo: &Path, home: &Path, name: &str) -> Result<PathBuf> {
    let path = prefixes_dir(home).join(name);
    if is_initialized(&path) {
        return Ok(path);
    }
    let ens = ensure_template(repo, home, "win64")?;
    if ens.get("status").and_then(|s| s.as_str()) != Some("PASS") {
        return Err(SmokeError::Message(format!(
            "ensure_template failed: {ens}"
        )));
    }
    let cloned = clone_prefix_from_template(repo, home, name, "win64")?;
    if cloned.get("status").and_then(|s| s.as_str()) != Some("PASS") {
        return Err(SmokeError::Message(format!(
            "clone_prefix failed: {cloned}"
        )));
    }
    if !is_initialized(&path) {
        return Err(SmokeError::Message(format!(
            "prefix not initialized: {}",
            path.display()
        )));
    }
    Ok(path)
}

fn wine_cmd(repo: &Path, prefix: &Path) -> Result<(PathBuf, Command)> {
    let pin = load_pin(repo).map_err(SmokeError::Engine)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(SmokeError::Message(format!(
            "vendored wine missing: {}",
            wine.display()
        )));
    }
    let mut argv: Vec<PathBuf> = Vec::new();
    if needs_xvfb() {
        if let Some(xvfb) = which("xvfb-run") {
            argv.push(xvfb);
        }
    }
    let mut cmd = if argv.is_empty() {
        let mut c = Command::new(&wine);
        apply_wine_env(&mut c, OptProfile::Optimized, prefix, "win64");
        c
    } else {
        let mut c = Command::new(&argv[0]);
        c.arg("-a");
        c.arg(&wine);
        apply_wine_env(&mut c, OptProfile::Optimized, prefix, "win64");
        c
    };
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    Ok((wine, cmd))
}

fn kill_prefix_wineserver(repo: &Path, prefix: &Path) {
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
}

fn read_child_output(child: &mut std::process::Child, timeout: Duration) -> Result<(String, String, Option<i32>)> {
    let started = Instant::now();
    let mut stdout = String::new();
    let mut stderr = String::new();
    loop {
        if let Some(status) = child.try_wait()? {
            if let Some(mut out) = child.stdout.take() {
                let _ = out.read_to_string(&mut stdout);
            }
            if let Some(mut err) = child.stderr.take() {
                let _ = err.read_to_string(&mut stderr);
            }
            return Ok((stdout, stderr, status.code()));
        }
        if started.elapsed() > timeout {
            let _ = child.kill();
            let _ = child.wait();
            if let Some(mut out) = child.stdout.take() {
                let _ = out.read_to_string(&mut stdout);
            }
            if let Some(mut err) = child.stderr.take() {
                let _ = err.read_to_string(&mut stderr);
            }
            return Err(SmokeError::Message(format!(
                "child timeout after {:?}; stdout={stdout} stderr={stderr}",
                timeout
            )));
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn run_same_prefix(
    repo: &Path,
    prefix: &Path,
    ac_exe: &Path,
    game_exe: &Path,
) -> Result<Value> {
    // Copy fixtures into prefix drive_c for stable Win paths.
    let dest_dir = prefix.join("drive_c/strawnt-interop");
    fs::create_dir_all(&dest_dir)?;
    let ac_dest = dest_dir.join("strawnt_ac_stub.exe");
    let game_dest = dest_dir.join("strawnt_game_stub.exe");
    fs::copy(ac_exe, &ac_dest)?;
    fs::copy(game_exe, &game_dest)?;

    let (_wine, mut ac_cmd) = wine_cmd(repo, prefix)?;
    ac_cmd.args([
        "C:\\strawnt-interop\\strawnt_ac_stub.exe",
        "--mode",
        "pipe",
        "--role",
        "listen",
        "--pipe",
        PIPE_NAME,
        "--expect",
        SAME_PAYLOAD,
        "--timeout-ms",
        "20000",
    ]);
    let mut ac_child = ac_cmd.spawn()?;

    // Give pipe server time to CreateNamedPipe.
    thread::sleep(Duration::from_millis(800));

    let (_wine2, mut game_cmd) = wine_cmd(repo, prefix)?;
    game_cmd.args([
        "C:\\strawnt-interop\\strawnt_game_stub.exe",
        "--mode",
        "pipe",
        "--role",
        "connect",
        "--pipe",
        PIPE_NAME,
        "--send",
        SAME_PAYLOAD,
        "--timeout-ms",
        "15000",
    ]);
    let mut game_child = game_cmd.spawn()?;

    let (g_out, g_err, g_code) = read_child_output(&mut game_child, Duration::from_secs(25))?;
    let (a_out, a_err, a_code) = read_child_output(&mut ac_child, Duration::from_secs(25))?;

    let ok = a_code == Some(0)
        && g_code == Some(0)
        && (a_out.contains(SAME_PAYLOAD) || a_out.contains("PASS"));
    Ok(json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "transport": "named_pipe",
        "pipe": PIPE_NAME,
        "payload": SAME_PAYLOAD,
        "ac": { "exit_code": a_code, "stdout_tail": tail(&a_out, 400), "stderr_tail": tail(&a_err, 400) },
        "game": { "exit_code": g_code, "stdout_tail": tail(&g_out, 400), "stderr_tail": tail(&g_err, 400) },
    }))
}

fn run_cross_prefix(
    repo: &Path,
    ac_prefix: &Path,
    game_prefix: &Path,
    ac_exe: &Path,
    game_exe: &Path,
) -> Result<Value> {
    let broker = BrokerHandle::start(BrokerConfig {
        bind: "127.0.0.1".into(),
        port: 0,
    })?;
    let port = broker.port();
    let token = format!("ntw4-{}", now_secs());
    let channel = "ntw4-cross";
    let ac_id = "pfx-ac";
    let game_id = "pfx-game";
    broker.grant(Grant {
        token: token.clone(),
        channel: channel.into(),
        prefixes: vec![ac_id.into(), game_id.into()],
    })?;

    for (pfx, exe_name, src) in [
        (ac_prefix, "strawnt_ac_stub.exe", ac_exe),
        (game_prefix, "strawnt_game_stub.exe", game_exe),
    ] {
        let dest_dir = pfx.join("drive_c/strawnt-interop");
        fs::create_dir_all(&dest_dir)?;
        fs::copy(src, dest_dir.join(exe_name))?;
    }

    // Start AC receiver first.
    let (_w, mut ac_cmd) = wine_cmd(repo, ac_prefix)?;
    ac_cmd.args([
        "C:\\strawnt-interop\\strawnt_ac_stub.exe",
        "--mode",
        "broker",
        "--role",
        "recv",
        "--host",
        "127.0.0.1",
        "--port",
        &port.to_string(),
        "--token",
        &token,
        "--prefix-id",
        ac_id,
        "--channel",
        channel,
        "--expect",
        CROSS_PAYLOAD,
        "--timeout-ms",
        "20000",
    ]);
    let mut ac_child = ac_cmd.spawn()?;
    thread::sleep(Duration::from_millis(500));

    let (_w2, mut game_cmd) = wine_cmd(repo, game_prefix)?;
    game_cmd.args([
        "C:\\strawnt-interop\\strawnt_game_stub.exe",
        "--mode",
        "broker",
        "--role",
        "send",
        "--host",
        "127.0.0.1",
        "--port",
        &port.to_string(),
        "--token",
        &token,
        "--prefix-id",
        game_id,
        "--channel",
        channel,
        "--send",
        CROSS_PAYLOAD,
        "--timeout-ms",
        "15000",
    ]);
    let mut game_child = game_cmd.spawn()?;

    let (g_out, g_err, g_code) = read_child_output(&mut game_child, Duration::from_secs(30))?;
    let (a_out, a_err, a_code) = read_child_output(&mut ac_child, Duration::from_secs(30))?;

    let ok = a_code == Some(0)
        && g_code == Some(0)
        && (a_out.contains(CROSS_PAYLOAD) || a_out.contains("PASS"));

    let report = json!({
        "status": if ok { "PASS" } else { "FAIL" },
        "transport": "host_broker_tcp",
        "broker_port": port,
        "channel": channel,
        "payload": CROSS_PAYLOAD,
        "ac_prefix_id": ac_id,
        "game_prefix_id": game_id,
        "ac": { "exit_code": a_code, "stdout_tail": tail(&a_out, 400), "stderr_tail": tail(&a_err, 400) },
        "game": { "exit_code": g_code, "stdout_tail": tail(&g_out, 400), "stderr_tail": tail(&g_err, 400) },
    });
    broker.stop();
    Ok(report)
}

fn tail(s: &str, n: usize) -> String {
    if s.len() <= n {
        s.to_string()
    } else {
        s[s.len() - n..].to_string()
    }
}

/// Full NTW4 smoke → JSON evidence object (caller may wrap with version/git).
pub fn run_interop_smoke(home: Option<&Path>) -> Result<Value> {
    let repo = find_repo_root()?;
    let home_buf = ensure_layout(home).map_err(SmokeError::Engine)?;

    let pin = load_pin(&repo)?;
    let (ac_exe, game_exe) = ensure_fixtures(&repo)?;

    let stamp = now_secs();
    let same_name = format!("ntw4-same-{stamp}");
    let ac_name = format!("ntw4-ac-{stamp}");
    let game_name = format!("ntw4-game-{stamp}");

    let same_pfx = make_prefix(&repo, &home_buf, &same_name)?;
    let ac_pfx = make_prefix(&repo, &home_buf, &ac_name)?;
    let game_pfx = make_prefix(&repo, &home_buf, &game_name)?;

    let same = run_same_prefix(&repo, &same_pfx, &ac_exe, &game_exe);
    kill_prefix_wineserver(&repo, &same_pfx);
    let same = same?;

    let cross = run_cross_prefix(&repo, &ac_pfx, &game_pfx, &ac_exe, &game_exe);
    kill_prefix_wineserver(&repo, &ac_pfx);
    kill_prefix_wineserver(&repo, &game_pfx);
    let cross = cross?;

    let same_ok = same.get("status").and_then(|s| s.as_str()) == Some("PASS");
    let cross_ok = cross.get("status").and_then(|s| s.as_str()) == Some("PASS");
    let status = if same_ok && cross_ok {
        "PASS"
    } else if same_ok || cross_ok {
        "PARTIAL"
    } else {
        "FAIL"
    };

    Ok(json!({
        "schema": "strawnt-ntw4-interop/v1",
        "stage": "ntw4-win32-ipc",
        "status": status,
        "product": "StrawNT",
        "execution_backend": "wine",
        "backend": "wine",
        "engine": "proton-ge",
        "pin": pin.tag,
        "engine_pin": pin.tag,
        "powered_by": "Wine",
        "powered_by_wine": true,
        "simulated": false,
        "same_prefix": same_ok,
        "cross_prefix": cross_ok,
        "same_prefix_result": same,
        "cross_prefix_result": cross,
        "fixtures": {
            "ac": ac_exe.display().to_string(),
            "game": game_exe.display().to_string(),
        },
        "home": home_buf.display().to_string(),
        "claims": {
            "same_prefix": same_ok,
            "cross_prefix": cross_ok,
            "ranked_pass_claimed": false,
            "full_windows_claimed": false,
            "powered_by_wine": true,
            "simulated": false,
            "vendor_anticheat_certified": false
        },
        "notes": [
            "NTW4 Win32 IPC: same_prefix named pipe + cross_prefix host broker",
            "Scene: anti-cheat App ↔ game message exchange (fixtures only)",
            "powered by Wine — not a ranked / vendor anti-cheat PASS",
            "cross-prefix default deny; smoke used explicit capability grant"
        ]
    }))
}
