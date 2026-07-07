use strawwu_device_proxy::devices::DeviceStatus;
use strawwu_device_proxy::mfp::{MfpSmokePayload, run_mfp_smoke};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MfpFormat {
    Text,
    Json,
}

/// Run `strawwu mfp smoke` and return formatted output plus payload.
pub fn run_mfp_smoke_command(format: MfpFormat) -> Result<(String, MfpSmokePayload), String> {
    let payload = run_mfp_smoke().map_err(|e| e.to_string())?;
    let out = match format {
        MfpFormat::Json => serde_json::to_string_pretty(&payload)
            .map_err(|e| format!("json encode failed: {e}"))?,
        MfpFormat::Text => format_mfp_text(&payload),
    };
    Ok((out, payload))
}

fn format_mfp_text(payload: &MfpSmokePayload) -> String {
    format!(
        "MFP smoke — {} ({}) — print={} scan={} aggregate={} mock={}",
        payload.printer.name,
        payload.printer.connection,
        payload.print.status.as_str(),
        payload.scan.status.as_str(),
        payload.aggregate.as_str(),
        payload.mock
    )
}

pub fn mfp_smoke_passed(payload: &MfpSmokePayload) -> bool {
    payload.aggregate == DeviceStatus::Pass
        && payload.printer.connection == "network"
        && payload.print.status == DeviceStatus::Pass
        && payload.scan.status == DeviceStatus::Pass
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mfp_smoke_json_fixture_pass() {
        std::env::set_var("STRAWWU_MFP_FIXTURE", "1");
        let (out, payload) = run_mfp_smoke_command(MfpFormat::Json).expect("mfp smoke json");
        assert!(out.contains("strawwu-mfp-smoke/v1"));
        assert_eq!(payload.printer.connection, "network");
        assert!(mfp_smoke_passed(&payload));
    }
}
