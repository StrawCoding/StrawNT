# W6-I4 Installed Boot 階段報告

| 任務 | w6-i4-installed-boot |
|------|----------------------|
| 版本 | 0.4.1.34 |
| 日期 | 2026-07-05 |
| Worker | 階段 31/47（w6-i4-installed-boot） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Calamares 安裝後，已安裝磁碟在 QEMU 上 **BIOS + UEFI** 雙模式開機，serial 輸出 **STRAWWU_BOOT_OK**。

## 交付物

| 類型 | 路徑 |
|------|------|
| E2E runner | `tests/install-e2e/run-installed-boot.sh` |
| 共用 boot 輔助 | `tests/install-e2e/lib.sh`（`run_installed_disk_boot`、OVMF） |
| GPT 分割（ESP+BIOS+root） | `tests/install-e2e/guest/modules/partition/main.py` |
| 雙 bootloader 安裝 | `tests/install-e2e/guest/e2e-bootloader-setup.sh` |
| Preflight | `tests/preflight/test-installed-boot.sh` |
| baseline | `docs/plans/baselines/installed-boot-baseline.json` |
| Makefile | `test-installed-boot`、`test-installed-boot-static`；`preflight` 含 W6-I4 |
| 結果 JSON | `tests/install-e2e/output/installed-boot-result.json` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 安裝管線 | 沿用 install-e2e Calamares Python partition + `e2e-bootloader-setup` |
| GPT 布局 | ESP 512M (ef00) + BIOS boot 2M (ef02) + root (8300) |
| BIOS 開機 | `grub-install --target=i386-pc` + QEMU pc/virtio `-boot c` |
| UEFI 開機 | `grub-install --target=x86_64-efi --no-nvram` + OVMF q35/virtio-blk |
| OVMF fallback | `EFI/BOOT/BOOTX64.EFI` + `EFI/BOOT/grub.cfg`（removable media 路徑） |
| 開機 marker | `strawwu-boot-marker.service` → serial `STRAWWU_BOOT_OK` |
| 快速重測 | `STRAWWU_INSTALLED_BOOT_SKIP_INSTALL=1` 跳過安裝、僅跑雙模式 boot |

## 治本修復紀錄

| 根因 | 修復 |
|------|------|
| partition 模組僅 BIOS boot + root，無 ESP | 改 GPT：ESP + BIOS boot + root，掛載 `/boot/efi` |
| ESP mount 在 root mount 前建立，被 mount 遮蓋 | 先 mount root，再 `makedirs boot/efi`，再 mount ESP |
| UEFI GRUB 未安裝（ESP 未掛載） | `ensure_target_mounts` 在 bootloader setup 重掛載 |
| OVMF 走 fallback 路徑卻進 UEFI Shell | 安裝 `EFI/BOOT/BOOTX64.EFI` |
| GRUB 載入後進 `grub>` rescue | 複製 `EFI/strawwu/grub.cfg` → `EFI/BOOT/grub.cfg` |

## 變更檔案清單

```
tests/install-e2e/run-installed-boot.sh                    (新增)
tests/install-e2e/lib.sh                                   (run_installed_disk_boot, OVMF)
tests/install-e2e/guest/modules/partition/main.py          (ESP+BIOS+root GPT)
tests/install-e2e/guest/e2e-bootloader-setup.sh            (UEFI GRUB + fallback)
tests/preflight/test-installed-boot.sh                     (新增)
docs/plans/baselines/installed-boot-baseline.json          (新增)
Makefile
VERSION (0.4.1.33 → 0.4.1.34)
docs/plans/stage-reports/W6-I4-installed-boot-report.md    (本檔)
```

## 驗收命令輸出（2026-07-05 UTC-4）

### `make test-installed-boot` — exit 0（~2463s / ~41 min，v4 完整 E2E）

Log: `/tmp/w6-i4-installed-boot-v4.log`

ISO: `StrawWU-0.4.1.33-amd64.iso`（dev-iso E2E）

結果 JSON: `tests/install-e2e/output/installed-boot-result.json`

```json
{
  "version": "0.4.1.34",
  "status": "PASS",
  "boot_marker": "STRAWWU_BOOT_OK",
  "install_ok": true,
  "bios_ok": true,
  "uefi_ok": true
}
```

| 階段 | 耗時 | 證據 |
|------|------|------|
| Calamares install | ~35 min | `tests/install-e2e/output/logs/installed-boot-live.log` 含 `STRAWWU-CALAMARES-INSTALL-OK` |
| BIOS installed boot | 130s | `tests/install-e2e/output/logs/installed-boot-bios.log` 含 `STRAWWU_BOOT_OK` |
| UEFI installed boot | 125s | `tests/install-e2e/output/logs/installed-boot-uefi.log` 含 `STRAWWU_BOOT_OK` |

### 快速重測（SKIP_INSTALL）— exit 0（~268s，2026-07-05T19:21）

Log: `/tmp/w6-i4-boot-retest.log`

`STRAWWU_INSTALLED_BOOT_SKIP_INSTALL=1` 重用 `installed-boot-disk.img`：BIOS 130s + UEFI 130s 均見 `STRAWWU_BOOT_OK`。

### `make preflight` — exit 0（~168s / ~268s）

Log: `/tmp/w6-i4-preflight-final.log`（首次）、`/tmp/w6-i4-preflight-verify.log`（本 session 重驗）

含 W0–W6-N5 全部階段 + **W6-I4 installed-boot**（`=== W6-I4 installed-boot done: PASS ===`）

## 已知限制

| 項目 | 狀態 |
|------|------|
| 完整 E2E 耗時 ~40–45 分 | 環境正常；日常可用 `STRAWWU_INSTALLED_BOOT_SKIP_INSTALL=1` 重測 boot |
| release-iso Phase 驗收 | 本 worker 用 dev-iso E2E ISO；release 驗收留待 Hermes trigger |
| firstboot / target identity | 本階段只驗 `STRAWWU_BOOT_OK`；firstboot 由 W6-N5 覆蓋 |
| 實機 UEFI NVRAM | E2E 用 `--no-nvram` + removable fallback；實機 Calamares 仍走正常 efibootmgr |

## VERSION

`0.4.1.33` → `0.4.1.34`（iterate）

## 建議 commit message

```
feat(w6): installed boot E2E — BIOS + UEFI STRAWWU_BOOT_OK

- run-installed-boot.sh: Calamares install → dual-mode disk boot
- partition module: GPT ESP + BIOS boot + root for UEFI installed boot
- e2e-bootloader-setup: UEFI GRUB + EFI/BOOT fallback grub.cfg
- lib.sh: run_installed_disk_boot with OVMF q35 support
Tests: make test-installed-boot PASS, make preflight PASS (0.4.1.34)
Version: 0.4.1.34
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T15:33:00-0400 | `[worker-START]` w6-i4-installed-boot |
| 2026-07-05T19:11:25-0400 | `[worker-DONE]` v4 完整 E2E PASS（install+bios+uefi） |
| 2026-07-05T19:21:27-0400 | `[worker-VERIFY]` SKIP_INSTALL 雙模式 boot 重測 PASS + preflight 重驗 PASS — 待 Hermes mark |
| 2026-07-05T19:34:55-0400 | `[worker-DONE]` 本 session 終驗：preflight exit 0（~221s）+ SKIP_INSTALL boot exit 0（~553s，BIOS/UEFI 各 130s STRAWWU_BOOT_OK）— 待 Hermes mark |

## 本 session 終驗輸出（2026-07-05T19:22–19:35 UTC-4）

### `make preflight` — exit 0（~221s）

Log: `/tmp/w6-i4-preflight-session.log`

含 W0–W6-I4 全部 preflight 階段；W6-I4 結尾：`=== W6-I4 installed-boot done: PASS ===`

### `make test-installed-boot`（SKIP_INSTALL）— exit 0（~553s）

Log: `/tmp/w6-i4-boot-final.log`

```json
{
  "version": "0.4.1.34",
  "status": "PASS",
  "boot_marker": "STRAWWU_BOOT_OK",
  "install_ok": true,
  "bios_ok": true,
  "uefi_ok": true,
  "tested": "2026-07-05T19:34:55-04:00"
}
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
export STRAWWU_ISO_PATH=os-image/output/StrawWU-0.4.1.33-amd64.iso
make test-installed-boot
make preflight
```

## 下一階段

**w6-f5-target-flathub**（Hermes mark PASS 後自動啟動，勿問使用者）。
