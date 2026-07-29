//! Real Windows PE/MSI execution via Wine (mature upstream substrate).
//!
//! Portable Core defaults to this backend so click-to-open actually runs apps.
//! `--backend native` keeps the in-process strawwu-nt simulated path for tests.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug, Clone)]
pub struct WineInfo {
    pub wine_bin: PathBuf,
    pub version: String,
    pub prefix: PathBuf,
}

#[derive(Debug, Clone)]
pub struct WineLaunchResult {
    pub pid: u32,
    pub wine_bin: PathBuf,
    pub prefix: PathBuf,
    pub cmdline: Vec<String>,
    pub exit_code: Option<i32>,
}

pub fn find_wine() -> Result<PathBuf, String> {
    if let Ok(p) = std::env::var("STRAWWU_WINE") {
        let path = PathBuf::from(p);
        if path.is_file() {
            return Ok(path);
        }
        return Err(format!("STRAWWU_WINE points to missing binary: {}", path.display()));
    }
    for name in ["wine64", "wine"] {
        if let Ok(path) = which(name) {
            return Ok(path);
        }
    }
    Err(
        "Wine not found. Install Wine, then re-run:\n  \
         Ubuntu/Debian: sudo apt install -y wine\n  \
         Fedora: sudo dnf install -y wine\n  \
         Arch: sudo pacman -S --noconfirm wine\n  \
         Or set STRAWWU_WINE=/path/to/wine"
            .into(),
    )
}

fn which(name: &str) -> Result<PathBuf, ()> {
    let out = Command::new("sh")
        .args(["-c", &format!("command -v {name}")])
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        return Err(());
    }
    Ok(PathBuf::from(s))
}

pub fn wine_prefix() -> PathBuf {
    if let Ok(p) = std::env::var("WINEPREFIX") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Ok(p) = std::env::var("STRAWWU_WINEPREFIX") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    if let Ok(prefix) = std::env::var("STRAWWU_PREFIX") {
        return PathBuf::from(prefix).join("var/lib/strawwu/wineprefix");
    }
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home).join(".local/share/strawwu-core/wineprefix");
    }
    PathBuf::from("/tmp/strawwu-wineprefix")
}

pub fn probe() -> Result<WineInfo, String> {
    let wine_bin = find_wine()?;
    let prefix = wine_prefix();
    let version = wine_version(&wine_bin).unwrap_or_else(|_| "unknown".into());
    Ok(WineInfo {
        wine_bin,
        version,
        prefix,
    })
}

fn wine_version(wine_bin: &Path) -> Result<String, String> {
    let out = Command::new(wine_bin)
        .arg("--version")
        .output()
        .map_err(|e| format!("failed to run {}: {e}", wine_bin.display()))?;
    if !out.status.success() {
        return Err(format!(
            "{} --version failed: {}",
            wine_bin.display(),
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn ensure_prefix(info: &WineInfo) -> Result<(), String> {
    fs::create_dir_all(&info.prefix)
        .map_err(|e| format!("create WINEPREFIX {}: {e}", info.prefix.display()))?;
    // First-time prefix init can be slow; skip if already initialized.
    if info.prefix.join("system.reg").is_file() {
        return Ok(());
    }
    let status = Command::new(&info.wine_bin)
        .env("WINEPREFIX", &info.prefix)
        .env("WINEDEBUG", "-all")
        .env("WINEDLLOVERRIDES", "mscoree,mshtml=")
        .args(["wineboot", "--init"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("wineboot --init failed to start: {e}"))?;
    if !status.success() {
        // Non-fatal on headless hosts without display — prefix dirs may still be usable.
        let _ = status;
    }
    Ok(())
}

fn is_msi(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| e.eq_ignore_ascii_case("msi"))
        .unwrap_or(false)
}

/// Build argv for Wine: MSI → msiexec /i; otherwise wine <path> [args…]
pub fn build_wine_argv(path: &Path, app_args: &[String], install_mode: bool) -> Vec<String> {
    let path_s = path.display().to_string();
    if is_msi(path) || (install_mode && is_msi(path)) {
        let mut v = vec!["msiexec".into(), "/i".into(), path_s];
        v.extend(app_args.iter().cloned());
        return v;
    }
    let mut v = vec![path_s];
    v.extend(app_args.iter().cloned());
    v
}

/// Launch a PE/MSI through Wine and wait for exit (installers / GUI apps).
pub fn run_wait(
    path: &Path,
    app_args: &[String],
    install_mode: bool,
) -> Result<WineLaunchResult, String> {
    let info = probe()?;
    ensure_prefix(&info)?;
    let argv = build_wine_argv(path, app_args, install_mode);
    let mut cmd = Command::new(&info.wine_bin);
    cmd.env("WINEPREFIX", &info.prefix)
        .env("WINEDEBUG", std::env::var("WINEDEBUG").unwrap_or_else(|_| "-all".into()))
        .args(&argv);
    let status = cmd
        .status()
        .map_err(|e| format!("failed to start Wine: {e}"))?;
    Ok(WineLaunchResult {
        pid: 0,
        wine_bin: info.wine_bin,
        prefix: info.prefix,
        cmdline: argv,
        exit_code: status.code(),
    })
}

/// Spawn Wine without waiting (for long-running apps from the CLI when detached).
pub fn run_spawn(
    path: &Path,
    app_args: &[String],
    install_mode: bool,
) -> Result<WineLaunchResult, String> {
    let info = probe()?;
    ensure_prefix(&info)?;
    let argv = build_wine_argv(path, app_args, install_mode);
    let mut cmd = Command::new(&info.wine_bin);
    cmd.env("WINEPREFIX", &info.prefix)
        .env("WINEDEBUG", std::env::var("WINEDEBUG").unwrap_or_else(|_| "-all".into()))
        .args(&argv)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let child = cmd
        .spawn()
        .map_err(|e| format!("failed to spawn Wine: {e}"))?;
    Ok(WineLaunchResult {
        pid: child.id(),
        wine_bin: info.wine_bin,
        prefix: info.prefix,
        cmdline: argv,
        exit_code: None,
    })
}

/// Status line helper for `strawwu status`.
pub fn status_line() -> String {
    match probe() {
        Ok(info) => format!(
            "wine: OK ({}) prefix={}",
            info.version,
            info.prefix.display()
        ),
        Err(e) => {
            let first = e.lines().next().unwrap_or("Wine not found");
            format!("wine: MISSING ({first})")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn msi_uses_msiexec() {
        let argv = build_wine_argv(Path::new("/tmp/pkg.msi"), &[], true);
        assert_eq!(argv[0], "msiexec");
        assert_eq!(argv[1], "/i");
        assert_eq!(argv[2], "/tmp/pkg.msi");
    }

    #[test]
    fn exe_passes_path_and_args() {
        let args = vec!["/S".into()];
        let argv = build_wine_argv(Path::new("/tmp/setup.exe"), &args, true);
        assert_eq!(argv, vec!["/tmp/setup.exe", "/S"]);
    }

    #[test]
    fn prefix_respects_env() {
        std::env::set_var("STRAWWU_WINEPREFIX", "/tmp/strawwu-test-wineprefix");
        assert_eq!(wine_prefix(), PathBuf::from("/tmp/strawwu-test-wineprefix"));
        std::env::remove_var("STRAWWU_WINEPREFIX");
    }
}
