# POST-DDP-rootfs — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-ddp-rootfs` |
| 版本 | `0.6.3.4`（`0.6.3.3` → `0.6.3.4`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T06:05+08:00 |
| Worker 回合 | 階段 1/8（worker 複驗） |

## 摘要

完成 Post-MVP DDP0–3 **device-proxy rootfs 整合**：新增 `strawwu-cli` crate 與 `strawwu devices list` CLI、`strawwu-device-proxy` Debian 套件（udev 規則 + hotplug 通知）、Hub「裝置」分頁（Tier 1–4 列舉），以及 COM 映射 smoke 腳本。

## 交付物

| 類型 | 路徑 |
|------|------|
| 規格（更新） | `components/specs/device-driver-proxy.md` |
| CLI crate | `components/strawwu-cli/` |
| launcher 整合 | `components/strawwu-launcher/src/cli.rs`, `main.rs` |
| Debian 套件 | `os-image/debs/strawwu-device-proxy/` |
| Hub 裝置分頁 | `hub/src/main/device-proxy-service.js` + `tab-devices` UI |
| Preflight gate | `tests/preflight/test-ddp-rootfs.sh` |
| COM smoke | `tests/device-proxy/test-com-map-smoke.sh` |
| Baseline | `docs/plans/baselines/device-proxy-hub-baseline.json` |

## 架構

```
strawwu-device-proxy crate (DeviceMatrix)
        │
        ▼ strawwu-cli::devices::list_devices
   strawwu devices list [--json]
        │
        ├─ udev 99-strawwu-device-proxy.rules (COM/HID/USB tags)
        ├─ hotplug-notify.sh → log + notify-send (DDP2)
        │
        ▼ Hub device-proxy-service.js (IPC)
   tab-devices — Tier summary + device cards
```

## DDP 對照

| Phase | 工作 | 狀態 |
|-------|------|------|
| DDP0 | rootfs CLI + udev 規則 | 完成 — `strawwu devices list` + `99-strawwu-device-proxy.rules` |
| DDP1 | Hub 裝置分頁 | 完成 — Tier 1–4 列舉 + fixture/dev 模式 |
| DDP2 | hotplug 通知 | 完成 — udev RUN + `hotplug-notify.sh` + toast |
| DDP3 | COM 映射 smoke | 完成 — `test-com-map-smoke.sh` |

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.3` → `0.6.3.4` |
| `components/strawwu-cli/` | **新增** devices list 實作 |
| `components/strawwu-launcher/` | 新增 `devices list` 子命令 |
| `os-image/debs/strawwu-device-proxy/` | **新增** udev + manifest + fixture |
| `hub/` | 裝置分頁 UI、service、i18n、測試 |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-device-proxy |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `target-manifest.yaml` | chroot 安裝順序 |
| `strawwu-desktop/debian/control` | Recommends strawwu-device-proxy |
| `tests/preflight/test-ddp-rootfs.sh` | 擴充完整 gate |

## 驗證命令輸出

### `make test-ddp-rootfs` — exit 0（2026-07-08T06:00+08:00 複驗）

Log: `/tmp/post-ddp-test-ddp-rootfs.log`

```
PASS: strawwu devices list / strawwu-cli / udev rules / deb artifact
PASS: Hub devices page artifact + tab-devices UI
PASS: cargo test strawwu-cli + strawwu devices list CLI smoke
PASS: DDP3 COM mapping smoke
PASS: hub npm test (82 tests)
=== POST-DDP rootfs done: PASS ===
```

### `make preflight` — exit 0（~310s，2026-07-08T06:00+08:00）

Log: `/tmp/post-ddp-preflight.log`

```
=== POST-HW4 peripherals done: PASS ===
=== Ubuntu 26.04 closeout done: PASS ===
=== FORK-F7 closeout done: PASS ===
（全鏈 53+ 靜態 gate PASS，無 FAIL 行）
```

## Git 狀態

變更尚未 commit（待 Hermes mark PASS 後由 companion 處理）。核心新增路徑：`components/strawwu-cli/`、`os-image/debs/strawwu-device-proxy/`、`hub/src/main/device-proxy-service.js`。

## 未做 / 誠實邊界

- Live USB 實機 USB 插拔 toast 證據（需硬體；本環境以 udev 規則 + 腳本單元測試覆蓋）
- Tier 4 VFIO 直通（留待 Phase 6.12 PoC）
- MFP 列印/掃描 E2E（`post-q3-mfp-smoke` 獨立 stage）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-ddp-rootfs
make preflight
```

證據路徑：
- `components/specs/device-driver-proxy.md`
- `docs/plans/stage-reports/POST-DDP-rootfs-report.md`
- `/tmp/post-ddp-test-ddp-rootfs.log`
- `/tmp/post-ddp-preflight.log`

## Commit message（建議）

```
feat(ddp): integrate device-proxy rootfs and Hub devices page

- Add strawwu-cli with `strawwu devices list [--json]`
- Ship strawwu-device-proxy deb (udev rules, hotplug notify)
- Hub tab-devices for Tier 1-4 device-proxy mappings
Tests: make test-ddp-rootfs PASS, make preflight PASS
Issue: v0.6.3.4
```
