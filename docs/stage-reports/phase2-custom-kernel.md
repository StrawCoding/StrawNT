# Stage Report: phase2-custom-kernel

- **階段 ID**: `phase2-custom-kernel` (3/8)
- **版本目標**: `0.3.0.0`
- **報告時間**: 2026-07-03T19:00+08:00
- **Worker**: Cursor Agent (Hermes Tick36 收尾 commit)
- **Commit**: `fb81a806e` fix(phase2): custom kernel boot path — initrd/casper/UEFI harness

## 階段目標

`kernel/build.sh` 產出 `linux-image-strawwu` .deb；`make swap-kernel` 替換 rootfs kernel；不複製 legacy bridge。

## 階段核心驗證（Hermes trigger-verify 命令）

### `make -C kernel build`

```
==> reusing existing linux-image-*strawwu*.deb (set STRAWWU_FORCE_KERNEL_BUILD=1 to rebuild)
==> produced kernel/output/linux-image-strawwu_6.8.12-1_amd64.deb (image+modules merged)
==> kernel build complete
```

- `.config`: `CONFIG_OVERLAY_FS=y`、`CONFIG_ISO9660_FS=y`（builtin）
- deb: `kernel/output/linux-image-strawwu_6.8.12-1_amd64.deb`（112MB @ 16:10）

### `make swap-kernel`

```
update-initramfs: Generating /boot/initrd.img-6.8.12-strawwu
==> kernel swap complete (6.8.12-strawwu)
```

`os-image/work/.swap-kernel-ok`:

```
strawwu-kernel:6.8.12-strawwu
```

### `tests/kernel/test-phase2.sh`

```
test-phase2: PASS — deb=.../linux-image-strawwu_6.8.12-1_amd64.deb vmlinuz=.../vmlinuz-6.8.12-strawwu
```

## Pipeline 全驗（Tick31 步驟 3–4）

| 步驟 | 結果 | 時間 |
|------|------|------|
| `make release-iso`（禁 SKIP_SQUASHFS） | 成功，6.0G ISO | 18:24 |
| `make preflight-iso-before-boot` | PASS | 18:25 |
| `STRAWWU_BOOT_TEST_MODES=bios,uefi bash tests/boot/run.sh` | **overall PASS** | 18:55 |

**最新 ISO**: `os-image/output/StrawWU-0.3.0.0-amd64.iso`  
**SHA256**: `aa6b3b4d51821381b061a42b955a16bbfcd6db58d7f139b4180a3dc4f4dc15f3`

### Boot-test 證據（release ISO @ 18:24）

`tests/boot/output/boot-result.json` @ 2026-07-03T18:55:36+08:00：

| 模式 | 狀態 | elapsed | marker |
|------|------|---------|--------|
| BIOS | PASS | 902s | STRAWWU_BOOT_OK |
| UEFI | PASS | 903s | STRAWWU_BOOT_OK |

（先前 ISO@17:03 雙模式亦 PASS @ 18:07，作為回歸確認。）

## 本階段技術修復摘要

1. **initrd preserve-main**：`main.zst` 位元組原樣保留，僅 early3 換 strawwu 模組 + branding premount，避免破壞 casper 掛載。
2. **overlay procfs 假陽性**：casper `setup_overlay` 前後檢查 `/proc/filesystems` 是否已有 `overlay`。
3. **Kernel builtin**：`OVERLAY_FS` + `ISO9660_FS` 內建，消除 initrd 模組路徑錯配。
4. **UEFI QEMU harness**：`tests/boot/run.sh` UEFI 改用 `virtio-scsi-pci` + `scsi-cd`（q35+ide-cd 無 `/dev/sr0`）。
5. **preflight pgrep 誤判**：改讀 `/proc/$pid/cmdline`，避免 Hermes supervisor 命令列觸發 false positive。

## 變更檔案

- `kernel/build.sh`
- `os-image/scripts/initrd-splice.py`
- `os-image/scripts/build-iso.sh`
- `os-image/config/branding/initrd/scripts/casper-premount/05strawwu-wait-live-media`
- `tests/boot/run.sh`
- `tests/preflight/test-iso-before-boot.sh`

## Worker 狀態

- **status**: `idle`（phase2 commit 完成；未手動跑 release-iso / boot-test，交由 pipeline）
- **驗證重跑** @ 19:00：`make -C kernel build` ✓、`make swap-kernel` ✓、`test-phase2.sh` ✓

## 建議 Hermes

**請執行 trigger-verify 並 mark 本階段**。證據齊全：

1. `os-image/work/.swap-kernel-ok` ✓
2. `kernel/output/linux-image-strawwu_6.8.12-1_amd64.deb` ✓
3. release ISO + SHA256SUMS ✓
4. preflight-iso-before-boot PASS ✓
5. boot-result.json BIOS+UEFI PASS ✓

本報告不自行宣稱 PASS/FAIL。
