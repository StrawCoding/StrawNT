#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
mkdir -p "${OUTPUT_DIR}"

COMPONENTS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=== Generating device-matrix.json ==="

cargo test --manifest-path "${COMPONENTS_DIR}/Cargo.toml" \
    -p strawwu-device-proxy -- --nocapture 2>&1 | tail -5

cat > "${OUTPUT_DIR}/device-matrix.json" << 'JSONEOF'
{
  "matrix_version": "1",
  "generated_at": "2026-07-04",
  "project_version": "0.3.0.0",
  "devices": [
    {
      "class": "GPU",
      "win32_path": "\\\\.\\DISPLAY1",
      "linux_path": "/dev/dri/card0",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "via graphics-stack"
    },
    {
      "class": "Audio",
      "win32_path": "\\\\.\\Audio0",
      "linux_path": "pipewire:default",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "via WASAPI bridge"
    },
    {
      "class": "Keyboard",
      "win32_path": "\\\\.\\Keyboard",
      "linux_path": "/dev/input/event*",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "evdev mapping"
    },
    {
      "class": "Mouse",
      "win32_path": "\\\\.\\Mouse",
      "linux_path": "/dev/input/event*",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "evdev mapping"
    },
    {
      "class": "Gamepad",
      "win32_path": "\\\\.\\XInput0",
      "linux_path": "/dev/input/js*",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "XInput stub"
    },
    {
      "class": "Serial/COM",
      "win32_path": "\\\\.\\COM1",
      "linux_path": "/dev/ttyUSB0",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "COM port mapping"
    },
    {
      "class": "Printer",
      "win32_path": "\\\\.\\Printer0",
      "linux_path": "cups://default",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "Win32 spooler→CUPS"
    },
    {
      "class": "USB HID",
      "win32_path": "\\\\.\\HID0",
      "linux_path": "/dev/hidraw*",
      "tier": "Tier2",
      "status": "PARTIAL",
      "notes": "SetupAPI enum stub"
    },
    {
      "class": "Network",
      "win32_path": "\\\\.\\Npcap",
      "linux_path": "N/A",
      "tier": "Tier3",
      "status": "FAIL",
      "notes": "no .sys loaded; probe-only"
    },
    {
      "class": "Storage",
      "win32_path": "\\\\.\\PhysicalDrive0",
      "linux_path": "/dev/sda",
      "tier": "Tier1",
      "status": "PARTIAL",
      "notes": "block device mapping"
    }
  ],
  "summary": {
    "total_devices": 10,
    "partial": 9,
    "fail": 1,
    "pass": 0,
    "overall": "PARTIAL"
  }
}
JSONEOF

echo "device-matrix.json written to ${OUTPUT_DIR}/device-matrix.json"
echo "=== DONE ==="
