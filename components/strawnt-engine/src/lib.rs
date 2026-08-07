//! StrawNT engine — vendored Proton-GE / Wine substrate (NTW1+) + shell (NTW2).
//!
//! Honesty: `execution_backend=wine`, `engine=proton-ge@<pin>`, powered by Wine.
//! Does not claim full Windows or ranked anti-cheat.
//!
//! NTW2: prefix / recipes / matrix (patterns absorbed from straw-wine).

pub mod matrix;
pub mod optimize;
pub mod paths;
pub mod prefix;
pub mod recipes;

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[derive(Debug, thiserror::Error)]
pub enum EngineError {
    #[error("{0}")]
    Message(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, EngineError>;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnginePin {
    pub engine: String,
    pub tag: String,
    pub sha512: String,
    pub distribution: String,
    pub tarball_url: String,
    pub dist_wine_relpath: String,
    pub raw: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineStatus {
    pub product: String,
    pub command: String,
    pub execution_backend: String,
    pub backend: String,
    pub engine: String,
    pub pin: String,
    pub engine_pin: String,
    pub powered_by_wine: bool,
    pub wine_bin: Option<String>,
    pub wine_version: Option<String>,
    pub dist_present: bool,
    pub cache_present: bool,
    pub distribution: String,
    pub status: String,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoctorReport {
    pub command: String,
    pub product: String,
    pub execution_backend: String,
    pub backend: String,
    pub engine: String,
    pub pin: String,
    pub engine_pin: String,
    pub powered_by: String,
    pub powered_by_wine: bool,
    pub status: String,
    pub wine: WineProbe,
    pub paths: BTreeMap<String, String>,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WineProbe {
    pub found: bool,
    pub wine_bin: Option<String>,
    pub version: Option<String>,
    pub flavor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunResult {
    pub status: String,
    pub backend: String,
    pub engine: String,
    pub pin: String,
    pub wine_bin: String,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub marker: Option<String>,
}

/// Resolve repository root (contains `VERSION` + `third_party/proton-ge`).
pub fn find_repo_root() -> Result<PathBuf> {
    if let Ok(override_root) = std::env::var("STRAWNT_ROOT") {
        let p = PathBuf::from(override_root);
        if p.join("third_party/proton-ge/PIN").is_file() {
            return Ok(p);
        }
        return Err(EngineError::Message(format!(
            "STRAWNT_ROOT={p:?} missing third_party/proton-ge/PIN"
        )));
    }

    let mut cur = std::env::current_dir()?;
    for _ in 0..12 {
        if cur.join("third_party/proton-ge/PIN").is_file() && cur.join("VERSION").is_file() {
            return Ok(cur);
        }
        if !cur.pop() {
            break;
        }
    }

    // Fallback: walk up from this crate when running from components/
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    if let Some(root) = manifest_dir.parent().and_then(|p| p.parent()) {
        if root.join("third_party/proton-ge/PIN").is_file() {
            return Ok(root.to_path_buf());
        }
    }

    Err(EngineError::Message(
        "could not locate StrawNT repo root (third_party/proton-ge/PIN)".into(),
    ))
}

pub fn ge_root(repo: &Path) -> PathBuf {
    repo.join("third_party/proton-ge")
}

pub fn load_pin(repo: &Path) -> Result<EnginePin> {
    let pin_path = ge_root(repo).join("PIN");
    let text = fs::read_to_string(&pin_path)?;
    if text.trim().is_empty() {
        return Err(EngineError::Message("PIN is empty".into()));
    }
    let mut raw = BTreeMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            raw.insert(k.trim().to_string(), v.trim().to_string());
        }
    }
    let get = |k: &str| -> Result<String> {
        raw.get(k)
            .cloned()
            .ok_or_else(|| EngineError::Message(format!("PIN missing {k}")))
    };
    Ok(EnginePin {
        engine: get("engine")?,
        tag: get("tag")?,
        sha512: get("sha512")?,
        distribution: get("distribution").unwrap_or_else(|_| "git-lfs".into()),
        tarball_url: get("tarball_url")?,
        dist_wine_relpath: raw
            .get("dist_wine_relpath")
            .cloned()
            .unwrap_or_else(|| "files/bin/wine".into()),
        raw,
    })
}

pub fn wine_bin_path(repo: &Path, pin: &EnginePin) -> PathBuf {
    ge_root(repo)
        .join("dist")
        .join(&pin.dist_wine_relpath)
}

pub fn probe_wine_version(wine_bin: &Path) -> Option<String> {
    let out = Command::new(wine_bin)
        .arg("--version")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;
    let mut s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        s = String::from_utf8_lossy(&out.stderr).trim().to_string();
    }
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

pub fn engine_status(repo: &Path) -> Result<EngineStatus> {
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    let dist_present = wine.is_file();
    let cache_name = pin
        .raw
        .get("tarball_name")
        .cloned()
        .unwrap_or_else(|| format!("{}.tar.gz", pin.tag));
    let cache_present = ge_root(repo).join("cache").join(&cache_name).is_file();
    let wine_version = if dist_present {
        probe_wine_version(&wine)
    } else {
        None
    };
    let status = if dist_present && wine_version.is_some() {
        "PASS"
    } else if cache_present {
        "PARTIAL"
    } else {
        "FAIL"
    };
    Ok(EngineStatus {
        product: "StrawNT".into(),
        command: "engine status".into(),
        execution_backend: "wine".into(),
        backend: "wine".into(),
        engine: "proton-ge".into(),
        pin: pin.tag.clone(),
        engine_pin: pin.tag.clone(),
        powered_by_wine: true,
        wine_bin: dist_present.then(|| wine.display().to_string()),
        wine_version,
        dist_present,
        cache_present,
        distribution: pin.distribution,
        status: status.into(),
        notes: vec![
            "execution_backend=wine".into(),
            format!("engine=proton-ge@{}", pin.tag),
            "powered by Wine".into(),
            "not a full Windows OS claim".into(),
            "not a ranked anti-cheat claim".into(),
        ],
    })
}

pub fn doctor(repo: &Path) -> Result<DoctorReport> {
    let status = engine_status(repo)?;
    let pin = load_pin(repo)?;
    let wine_path = wine_bin_path(repo, &pin);
    let found = wine_path.is_file();
    let version = status.wine_version.clone();
    let mut paths = BTreeMap::new();
    paths.insert("repo".into(), repo.display().to_string());
    paths.insert("ge_root".into(), ge_root(repo).display().to_string());
    paths.insert("pin_file".into(), ge_root(repo).join("PIN").display().to_string());
    paths.insert("dist".into(), ge_root(repo).join("dist").display().to_string());
    paths.insert("cache".into(), ge_root(repo).join("cache").display().to_string());
    if found {
        paths.insert("wine_bin".into(), wine_path.display().to_string());
    }
    Ok(DoctorReport {
        command: "doctor".into(),
        product: "StrawNT".into(),
        execution_backend: "wine".into(),
        backend: "wine".into(),
        engine: "proton-ge".into(),
        pin: pin.tag.clone(),
        engine_pin: pin.tag.clone(),
        powered_by: "Wine".into(),
        powered_by_wine: true,
        status: status.status,
        wine: WineProbe {
            found,
            wine_bin: found.then(|| wine_path.display().to_string()),
            version,
            flavor: "proton-ge".into(),
        },
        paths,
        notes: status.notes,
    })
}

/// Run a simple cmd.exe echo through vendored Wine (hello smoke).
pub fn run_hello_cmd(repo: &Path, prefix: &Path) -> Result<RunResult> {
    let pin = load_pin(repo)?;
    let wine = wine_bin_path(repo, &pin);
    if !wine.is_file() {
        return Err(EngineError::Message(format!(
            "vendored wine missing at {}; run scripts/fetch-proton-ge.sh",
            wine.display()
        )));
    }
    fs::create_dir_all(prefix)?;
    let marker = format!(
        "STRAWNT_HELLO_{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    );
    let script = format!("echo {marker}");
    let mut command = Command::new(&wine);
    command
        .arg("cmd")
        .arg("/c")
        .arg(&script)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // NTW3: product default = optimized Wine env (quiet + esync/fsync).
    optimize::apply_wine_env(
        &mut command,
        optimize::OptProfile::Optimized,
        prefix,
        "win64",
    );
    let output = command.output()?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let exit_code = output.status.code().unwrap_or(-1);
    let ok = exit_code == 0 && stdout.contains(&marker);
    Ok(RunResult {
        status: if ok { "PASS".into() } else { "FAIL".into() },
        backend: "wine".into(),
        engine: "proton-ge".into(),
        pin: pin.tag,
        wine_bin: wine.display().to_string(),
        stdout,
        stderr,
        exit_code,
        marker: Some(marker),
    })
}

pub fn print_status_human(s: &EngineStatus) {
    println!("strawnt engine status");
    println!("  backend         : {}", s.backend);
    println!("  execution_backend: {}", s.execution_backend);
    println!("  engine          : {}@{}", s.engine, s.pin);
    println!("  pin             : {}", s.pin);
    println!("  distribution    : {}", s.distribution);
    println!("  powered by      : Wine");
    println!("  status          : {}", s.status);
    println!(
        "  wine_bin        : {}",
        s.wine_bin.as_deref().unwrap_or("(missing — run fetch-proton-ge.sh)")
    );
    println!(
        "  wine_version    : {}",
        s.wine_version.as_deref().unwrap_or("(unknown)")
    );
    println!("  dist_present    : {}", s.dist_present);
    println!("  cache_present   : {}", s.cache_present);
}

pub fn print_doctor_human(d: &DoctorReport) {
    println!("strawnt doctor");
    println!("  product         : {}", d.product);
    println!("  backend         : {}", d.backend);
    println!("  execution_backend: {}", d.execution_backend);
    println!("  engine          : {}@{}", d.engine, d.pin);
    println!("  powered by      : {}", d.powered_by);
    println!("  status          : {}", d.status);
    println!("  wine.found      : {}", d.wine.found);
    println!(
        "  wine.bin        : {}",
        d.wine.wine_bin.as_deref().unwrap_or("(missing)")
    );
    println!(
        "  wine.version    : {}",
        d.wine.version.as_deref().unwrap_or("(unknown)")
    );
    println!("  wine.flavor     : {}", d.wine.flavor);
    for (k, v) in &d.paths {
        println!("  path.{k:<12}: {v}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pin_roundtrip_from_repo() {
        let root = find_repo_root().expect("repo root");
        let pin = load_pin(&root).expect("pin");
        assert_eq!(pin.engine, "proton-ge");
        assert!(!pin.tag.is_empty());
        assert_eq!(pin.sha512.len(), 128);
        assert_eq!(pin.distribution, "git-lfs");
    }
}
