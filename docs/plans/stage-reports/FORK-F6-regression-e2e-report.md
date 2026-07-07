# FORK-F6-regression-e2e — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f6-regression-e2e` |
| 版本 | `0.6.2.5`（`0.6.2.4` → `0.6.2.5`） |
| 基底 | Ubuntu 26.04 **resolute** fork snapshot（F1 baseline） |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07T23:44+08:00 |

## 摘要

在 **fork-sync-base** 還原的 fork 基底上完成 release-iso 全回歸驗證鏈：BIOS+UEFI boot-test、install-firstboot E2E（`FIRSTBOOT_OK`），並新增 fork 專用回歸 marker 與 preflight gate。證明 fork 快照路徑可取代 clone 路徑產出可安裝、可開機、可完成 firstboot 的 release ISO。

## 交付物

| 類型 | 路徑 |
|------|------|
| 回歸 marker 腳本 | `tests/fork/write-regression-marker.sh` |
| Preflight gate | `tests/preflight/test-fork-f6-regression-e2e.sh`（完整證據驗證） |
| Fork 回歸 marker | `os-image/work/.fork-regression-e2e-ok` |
| Fork sync marker | `os-image/work/.fork-sync-base-ok` |
| release ISO | `os-image/output/StrawWU-0.6.2.5-amd64.iso`（4.86 GiB） |
| boot-test 證據 | `tests/boot/output/boot-result.json` |
| firstboot E2E 證據 | `tests/install-e2e/output/firstboot-e2e-result.json` |

## 架構

```
fork-base/snapshots/*.tar.zst
        │
        ▼ make fork-sync-base
   .fork-sync-base-ok + rootfs (resolute)
        │
        ▼ make release-iso (swap-kernel + branding + squashfs xz)
   StrawWU-0.6.2.5-amd64.iso
        │
        ├── make boot-test-release-iso → STRAWWU_BOOT_OK (BIOS+UEFI)
        └── make test-install-firstboot-e2e → FIRSTBOOT_OK
                │
                ▼ tests/fork/write-regression-marker.sh
           .fork-regression-e2e-ok
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.4` → `0.6.2.5` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `tests/fork/write-regression-marker.sh` | **新增** fork 回歸 marker 寫入 |
| `tests/preflight/test-fork-f6-regression-e2e.sh` | 強化為完整 E2E 證據 gate |
| `tests/boot/output/boot-result.json` | 0.6.2.5 BIOS+UEFI PASS |
| `tests/install-e2e/output/firstboot-e2e-result.json` | 0.6.2.5 install+boot+firstboot PASS |
| `os-image/work/.fork-sync-base-ok` | fork restore 完成 |
| `os-image/work/.fork-regression-e2e-ok` | fork 回歸鏈完成 |

## 驗證命令輸出

### `make fork-sync-base` — exit 0（~492s）

Log: `/tmp/fork-f6-fork-sync-base.log`

```
==> restoring fork snapshot: .../fork-baseline-0.6.2.0-20260707T110640Z.tar.zst
==> fork-sync-base OK (mode=restore)
```

### `make release-iso` — exit 0（~1803s）

Log: `/tmp/fork-f6-release-iso.log`

```
==> build complete (release-iso): .../StrawWU-0.6.2.5-amd64.iso
071c28f3bbfa1cfc38a38882ad7b7de6b7ef78b770584d701757240c22e0cc58  StrawWU-0.6.2.5-amd64.iso
```

### `make boot-test-release-iso` — exit 0（~805s）

Log: `/tmp/fork-f6-boot-test.log`

| 模式 | 耗時 | 結果 |
|------|------|------|
| BIOS | 389s | STRAWWU_BOOT_OK |
| UEFI | 381s | STRAWWU_BOOT_OK |

### `make test-install-firstboot-e2e` — exit 0（~5720s）

Log: `/tmp/fork-f6-firstboot-e2e.log`

```json
{
  "version": "0.6.2.5",
  "status": "PASS",
  "firstboot_marker": "FIRSTBOOT_OK",
  "install_ok": true,
  "boot_ok": true,
  "firstboot_ok": true
}
```

### `make test-fork-f6-regression-e2e` — exit 0（~0.2s）

Log: `/tmp/fork-f6-test.log`

```
PASS: fork manifest Ubuntu 26.04.0 resolute
PASS: fork-sync-base marker present
PASS: release ISO StrawWU-0.6.2.5-amd64.iso (4860 MiB)
PASS: boot-result 0.6.2.5 BIOS+UEFI STRAWWU_BOOT_OK
PASS: firstboot-e2e 0.6.2.5 install+boot+FIRSTBOOT_OK
PASS: .fork-regression-e2e-ok fork resolute 0.6.2.5
FORK-F6 REGRESSION E2E OK
```

### `make preflight` — exit 0（前 ~198s / 後 ~324s / 重驗 ~201s）

Log: `/tmp/fork-f6-preflight-pre.log`、`/tmp/fork-f6-preflight-post.log`、`/tmp/fork-f6-preflight-verify.log`

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

### 本輪 companion 重驗（2026-07-07T23:34–23:38）

| 命令 | exit | log |
|------|------|-----|
| `make test-fork-f6-regression-e2e` | 0 | `/tmp/fork-f6-verify-test.log` |
| `make preflight` | 0 | `/tmp/fork-f6-preflight-verify.log` |

完整 E2E 鏈（fork-sync-base → release-iso → boot-test → firstboot-e2e）已於前序 worker 執行完畢；證據 JSON 與 marker 仍有效，本輪僅重跑 gate + preflight。

### companion TICK 重驗（2026-07-07T23:40–23:44）

Hermes `[worker-TICK] periodic companion check` 觸發；worker 重跑 gate + preflight 確認證據仍有效。

| 命令 | exit | 耗時 | log |
|------|------|------|-----|
| `make test-fork-f6-regression-e2e` | 0 | ~0.1s | `/tmp/fork-f6-companion-test.log` |
| `make preflight` | 0 | ~201s | `/tmp/fork-f6-companion-preflight.log` |

```
FORK-F6 REGRESSION E2E OK
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

完整 E2E 鏈（fork-sync-base → release-iso → boot-test → firstboot-e2e）無需重跑；既有證據與 marker 仍對齊 `VERSION=0.6.2.5`。

## 證據路徑

| 項目 | 路徑 |
|------|------|
| release ISO | `os-image/output/StrawWU-0.6.2.5-amd64.iso` |
| boot-test | `tests/boot/output/boot-result.json` |
| firstboot E2E | `tests/install-e2e/output/firstboot-e2e-result.json` |
| fork regression marker | `os-image/work/.fork-regression-e2e-ok` |
| fork sync marker | `os-image/work/.fork-sync-base-ok` |
| rootfs os-release | `VERSION=0.6.2.5`, `VERSION_CODENAME=resolute` |

## 主要 log

| 步驟 | log |
|------|-----|
| preflight（前） | `/tmp/fork-f6-preflight-pre.log` |
| fork-sync-base | `/tmp/fork-f6-fork-sync-base.log` |
| release-iso | `/tmp/fork-f6-release-iso.log` |
| boot-test | `/tmp/fork-f6-boot-test.log` |
| firstboot E2E | `/tmp/fork-f6-firstboot-e2e.log` |
| write marker | `/tmp/fork-f6-write-marker.log` |
| test-fork-f6 | `/tmp/fork-f6-test.log` |
| preflight（後） | `/tmp/fork-f6-preflight-post.log` |

## 備註

- `base_mode` 仍為 `clone`（fork-f7-closeout 才切換預設為 `fork`）。
- fork 快照來源為 F1 baseline（`0.6.2.0`）；release-iso 以當前 `VERSION`（`0.6.2.5`）重新 branding + swap-kernel。
- `.clone-ubuntu-base-ok` 與 `.fork-sync-base-ok` 並存；`base-marker.sh` 優先辨識 fork marker。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f6-regression-e2e
make preflight
```

## Commit message（建議）

```
feat(fork-f6): fork base regression E2E on release-iso

- Add tests/fork/write-regression-marker.sh + .fork-regression-e2e-ok
- Strengthen test-fork-f6-regression-e2e gate for boot+install evidence
- VERSION 0.6.2.4 → 0.6.2.5; evidence from fork-sync-base release chain
Tests: make test-fork-f6-regression-e2e PASS; make preflight PASS
```
