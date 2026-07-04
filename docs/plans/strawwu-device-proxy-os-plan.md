# StrawWU Device Proxy OS 整合計畫

| 代號 | DDP0–DDP3 |
|------|-----------|
| 對齊 | Phase 6.11 · Hub |

## 缺口

`strawwu-device-proxy` cargo 29 tests PASS，但 rootfs 無 udev 規則、Hub 無裝置分頁。

## Phase

| Phase | 工作 | DoD |
|-------|------|-----|
| DDP0 | rootfs 納入 CLI + udev 規則 | `strawwu devices list` 在 Live |
| DDP1 | Hub「裝置」分頁 | 列舉 Tier1–4 |
| DDP2 | hotplug 通知 | 插拔 USB 顯示 toast |
| DDP3 | 安裝後 E2E | COM 映射 smoke |

## Wave

W5–W6（v0.5 可 PARTIAL，v1.0 完整）
