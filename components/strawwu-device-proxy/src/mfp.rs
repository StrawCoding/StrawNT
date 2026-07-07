use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};

use crate::devices::DeviceStatus;

const DEFAULT_FIXTURE: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../tests/device-proxy/fixtures/mfp-network-printer.json"
));

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkMfpPrinter {
    pub id: String,
    pub name: String,
    pub win32_printer: String,
    pub cups_uri: String,
    pub scan_uri: String,
    pub connection: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MfpChannelResult {
    pub status: DeviceStatus,
    pub backend: String,
    pub mock: bool,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MfpSmokePayload {
    pub schema: String,
    pub printer: NetworkMfpPrinter,
    pub print: MfpChannelResult,
    pub scan: MfpChannelResult,
    pub aggregate: DeviceStatus,
    pub mock: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MfpFixtureCatalog {
    schema: String,
    mock: bool,
    printers: Vec<NetworkMfpPrinter>,
    print: MfpChannelResult,
    scan: MfpChannelResult,
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum MfpError {
    #[error("no network MFP printer configured")]
    NoPrinter,
    #[error("fixture parse failed: {0}")]
    Fixture(String),
    #[error("probe failed: {0}")]
    Probe(String),
}

fn fixture_path() -> PathBuf {
    if let Ok(path) = std::env::var("STRAWWU_MFP_FIXTURE_PATH") {
        return PathBuf::from(path);
    }
    PathBuf::from("/usr/share/strawwu/device-proxy/mfp-fixture-catalog.json")
}

fn dev_fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../tests/device-proxy/fixtures/mfp-network-printer.json")
}

fn use_fixture_mode() -> bool {
    if std::env::var("STRAWWU_MFP_FIXTURE").as_deref() == Ok("1") {
        return true;
    }
    !command_exists("lpstat")
}

fn command_exists(cmd: &str) -> bool {
    Command::new("sh")
        .arg("-c")
        .arg(format!("command -v {cmd}"))
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn read_fixture_file(path: &Path) -> Result<MfpFixtureCatalog, MfpError> {
    let raw = fs::read_to_string(path)
        .map_err(|e| MfpError::Fixture(format!("read {}: {e}", path.display())))?;
    serde_json::from_str(&raw).map_err(|e| MfpError::Fixture(e.to_string()))
}

fn load_fixture_catalog() -> Result<MfpFixtureCatalog, MfpError> {
    for path in [fixture_path(), dev_fixture_path()] {
        if path.is_file() {
            return read_fixture_file(&path);
        }
    }
    serde_json::from_str(DEFAULT_FIXTURE).map_err(|e| MfpError::Fixture(e.to_string()))
}

fn pick_network_printer(catalog: &MfpFixtureCatalog) -> Result<NetworkMfpPrinter, MfpError> {
    catalog
        .printers
        .iter()
        .find(|p| p.connection == "network")
        .cloned()
        .ok_or(MfpError::NoPrinter)
}

fn probe_cups_print(printer: &NetworkMfpPrinter) -> MfpChannelResult {
    if use_fixture_mode() {
        if let Ok(catalog) = load_fixture_catalog() {
            return catalog.print;
        }
    }

    let output = Command::new("lpstat")
        .arg("-p")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default();

    let uri_hit = output.contains(&printer.cups_uri)
        || output.to_ascii_lowercase().contains(&printer.name.to_ascii_lowercase());

    if uri_hit || output.contains("printer") {
        MfpChannelResult {
            status: DeviceStatus::Pass,
            backend: "cups".into(),
            mock: false,
            notes: "Win32 spooler→CUPS IPP print job path".into(),
        }
    } else {
        MfpChannelResult {
            status: DeviceStatus::Partial,
            backend: "cups".into(),
            mock: false,
            notes: "CUPS present but target network printer not enumerated".into(),
        }
    }
}

fn probe_scan(printer: &NetworkMfpPrinter) -> MfpChannelResult {
    if use_fixture_mode() {
        if let Ok(catalog) = load_fixture_catalog() {
            return catalog.scan;
        }
    }

    if command_exists("scanimage") {
        let output = Command::new("scanimage")
            .arg("-L")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
            .unwrap_or_default();
        if output.contains("ipp://") || output.contains("escl:") {
            return MfpChannelResult {
                status: DeviceStatus::Pass,
                backend: "sane-ipp".into(),
                mock: false,
                notes: "SANE/IPP scan backend".into(),
            };
        }
    }

    if printer.scan_uri.starts_with("ipp://") || printer.scan_uri.starts_with("escl:") {
        MfpChannelResult {
            status: DeviceStatus::Partial,
            backend: "sane-ipp".into(),
            mock: false,
            notes: format!("configured scan URI {} (probe unavailable)", printer.scan_uri),
        }
    } else {
        MfpChannelResult {
            status: DeviceStatus::Fail,
            backend: "sane-ipp".into(),
            mock: false,
            notes: "no scan backend detected".into(),
        }
    }
}

fn aggregate_status(print: &MfpChannelResult, scan: &MfpChannelResult) -> DeviceStatus {
    match (print.status, scan.status) {
        (DeviceStatus::Pass, DeviceStatus::Pass) => DeviceStatus::Pass,
        (DeviceStatus::Fail, _) | (_, DeviceStatus::Fail) => DeviceStatus::Fail,
        _ => DeviceStatus::Partial,
    }
}

/// Run MFP print+scan smoke for one network printer (fixture or live CUPS/SANE).
pub fn run_mfp_smoke() -> Result<MfpSmokePayload, MfpError> {
    let catalog = load_fixture_catalog()?;
    let printer = pick_network_printer(&catalog)?;
    let mock = use_fixture_mode() || catalog.mock;

    let print = if mock {
        catalog.print.clone()
    } else {
        probe_cups_print(&printer)
    };
    let scan = if mock {
        catalog.scan.clone()
    } else {
        probe_scan(&printer)
    };
    let aggregate = aggregate_status(&print, &scan);

    Ok(MfpSmokePayload {
        schema: "strawwu-mfp-smoke/v1".into(),
        printer,
        print,
        scan,
        aggregate,
        mock,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_smoke_passes_network_printer() {
        std::env::set_var("STRAWWU_MFP_FIXTURE", "1");
        let payload = run_mfp_smoke().expect("fixture smoke");
        assert_eq!(payload.schema, "strawwu-mfp-smoke/v1");
        assert_eq!(payload.printer.connection, "network");
        assert_eq!(payload.print.status, DeviceStatus::Pass);
        assert_eq!(payload.scan.status, DeviceStatus::Pass);
        assert_eq!(payload.aggregate, DeviceStatus::Pass);
        assert!(payload.mock);
    }

    #[test]
    fn aggregate_requires_both_channels() {
        let pass = MfpChannelResult {
            status: DeviceStatus::Pass,
            backend: "cups".into(),
            mock: true,
            notes: String::new(),
        };
        let partial = MfpChannelResult {
            status: DeviceStatus::Partial,
            backend: "sane".into(),
            mock: true,
            notes: String::new(),
        };
        assert_eq!(aggregate_status(&pass, &pass), DeviceStatus::Pass);
        assert_eq!(aggregate_status(&pass, &partial), DeviceStatus::Partial);
    }
}
