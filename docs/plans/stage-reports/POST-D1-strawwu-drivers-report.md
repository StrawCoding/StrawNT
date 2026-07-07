# POST-D1-strawwu-drivers — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-d1-strawwu-drivers` |
| 版本 | `0.6.2.7`（`0.6.2.6` → `0.6.2.7`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T00:28+08:00 |
| Worker 回合 | 階段 1/8 續跑驗證（Hermes TICK IN_PROGRESS） |

## 摘要

實作 Post-MVP D1 **strawwu-drivers**：新增 `strawwu-drivers` Debian 套件（包裝 `ubuntu-drivers` CLI + polkit 安裝授權 + fixture 開發模式），並在 StrawWU Hub 新增「驅動」分頁，顯示 NVIDIA/AMD/Intel GPU 硬體、推薦驅動、安裝狀態與 Secure Boot 誠實警告（連結 `post-sec-secureboot-route`）。對標 Linux Mint Driver Manager / Ubuntu Additional Drivers UX。

## 交付物

| 類型 | 路徑 |
|------|------|
| 計畫 | `docs/plans/strawwu-drivers-plan.md` |
| Debian 套件 | `os-image/debs/strawwu-drivers/` |
| Hub 驅動分頁 | `hub/src/main/drivers-service.js` + renderer 面板 |
| Preflight gate | `tests/preflight/test-drivers.sh` |
| Baseline | `docs/plans/baselines/drivers-hub-baseline.json` |
| Python 單元測試 | `os-image/debs/strawwu-drivers/tests/test-drivers.py` |
| Hub 單元測試 | `hub/test/drivers.test.js` |

## 架構

```
ubuntu-drivers / lspci / mokutil
        │
        ▼ strawwu-drivers CLI (list|status|install|devices)
   polkit: xyz.wastebase.strawwu.drivers.install
        │
        ▼ Hub drivers-service.js (IPC)
   tab-drivers UI — GPU cards + install buttons
        │
        ▼ Secure Boot 警告 → post-sec-secureboot-route
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.6` → `0.6.2.7` |
| `hub/package.json` | 版本同步 |
| `os-image/debs/strawwu-drivers/` | **新增** CLI、core.py、polkit、manifest、fixture |
| `hub/src/main/drivers-service.js` | **新增** Hub 後端服務 |
| `hub/src/renderer/index.html` | 驅動分頁 UI |
| `hub/src/renderer/renderer.js` | 驅動渲染與安裝流程 |
| `hub/src/renderer/styles.css` | 驅動卡片與 SB 警告樣式 |
| `hub/locales/en.json`, `zh.json` | drivers.* i18n |
| `hub/resources/settings-manifest.json` | drivers panel 註冊 |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-drivers 建置 |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | chroot 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends strawwu-drivers |
| `tests/preflight/test-drivers.sh` | 擴充 OS 整合 + deb artifact 閘門 |

## 功能範圍

### 已完成（v0.6 D1）

- `strawwu-drivers list|status|install|devices` — 包裝 `ubuntu-drivers`
- Hub「驅動」分頁：GPU 型號、推薦驅動、安裝狀態、一鍵安裝
- NVIDIA/AMD/Intel fixture 各 1 筆（開發/mock 模式）
- Secure Boot 啟用時誠實警告 + 連結 SEC 計畫 ID
- polkit `auth_admin_keep` 安裝授權
- OS 映像整合：`build-os-debs` / `target-manifest` / `strawwu-desktop` Recommends

### 未做（留待後續 stage）

- 實機 NVIDIA Live 安裝證據（需硬體或 QEMU GPU passthrough）
- firstboot GPU 提示（計畫標為可選）
- ROCm 策展、自簽 kernel module

## 驗證命令輸出

### `make test-drivers` — exit 0

Log: `/tmp/post-d1-test-drivers.log`

```
PASS: strawwu-drivers deb / CLI / core / manifest / fixture / polkit
PASS: target-manifest + build-os-debs + desktop Recommends integration
PASS: strawwu-drivers deb artifact
PASS: hub drivers-service + fixture
PASS: renderer tab-drivers + drivers-devices + drivers-packages + secure-boot
PASS: settings manifest drivers panel
PASS: IPC GET_DRIVERS_STATUS + INSTALL_DRIVER
Ran 9 tests — OK (python)
PASS: hub npm test (74 tests)
=== POST-D1 strawwu-drivers done: PASS ===
EXIT:0
```

### `make preflight` — exit 0（~201s）

Log: `/tmp/post-d1-preflight.log`

全鏈 53+ 靜態 gate PASS（含既有 MVP/Wave/Post-MVP infra gate）。本階段專屬 gate 為 `make test-drivers`（尚未納入全域 preflight 鏈，由 Hermes `trigger-verify` 獨立執行）。

```
# 尾端摘要（2026-07-08T00:28+08:00）
=== FORK-F7 closeout done: PASS ===
EXIT:0
```

## Live 硬體證據

| 廠商 | 狀態 | 說明 |
|------|------|------|
| NVIDIA | **FIXTURE** | mock catalog `10de:2484` RTX 3070；實機 Live 待 HW track |
| AMD | **FIXTURE** | mock catalog `1002:73bf` RX 6800 XT |
| Intel iGPU | **FIXTURE** | mock catalog `8086:9a49` Iris Xe |

> 計畫要求 ≥1 各廠商 Live PASS；本 worker 環境無 GPU 實機，以 fixture + 單元測試覆蓋偵測邏輯。NVIDIA 實機證據誠實標記 SKIP，建議 Hermes 於 `post-hw-t1-live-usb` 補證。

## 測試摘要

| 命令 | exit | 說明 |
|------|------|------|
| `make test-drivers` | 0 | POST-D1 專屬 gate |
| `make preflight` | 0 | 全域靜態完整性 |
| `python3 os-image/debs/strawwu-drivers/tests/test-drivers.py` | 0 | 9 tests OK |
| `cd hub && npm test` | 0 | 74 tests OK（含 drivers.test.js） |

## 建議 commit message

```
feat(post-d1): add strawwu-drivers CLI and Hub drivers page

- New strawwu-drivers deb wrapping ubuntu-drivers with polkit install
- Hub drivers tab: GPU devices, recommended packages, Secure Boot warning
- Fixture catalog for NVIDIA/AMD/Intel dev mode; test-drivers preflight gate
Tests: make test-drivers PASS; make preflight PASS
Version: 0.6.2.7
```

## 續跑狀態

| 項目 | 狀態 |
|------|------|
| 實作 | 完成（未 commit；見 `git status`） |
| `make test-drivers` | exit 0 |
| `make preflight` | exit 0 |
| 待辦 | Hermes mark PASS；NVIDIA 實機 Live 證據留 `post-hw-t1-live-usb` |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-drivers && make preflight
```

## 後續

Hermes mark PASS → 自動啟動下一 Post-MVP stage（見 `kickoff/POST-MVP-AUTO-SEQUENCE.md`）。
