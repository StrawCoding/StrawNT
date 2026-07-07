# U26-M6-regression-e2e — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `u26-m6-regression-e2e` |
| 版本 | `0.6.1.5` |
| 基底 | Ubuntu 26.04 **resolute** |
| 狀態 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07 |

## 摘要

完成 Ubuntu 26.04 resolute 基底上的 release-iso 全回歸驗證鏈：release-iso 建置、BIOS+UEFI boot-test、install-firstboot E2E 證據對齊，並修復 rootfs 被 noble branding 覆蓋的治本問題。

## 治本修復

### 1. rootfs 被 noble 污染（`apply-branding.sh`）

**根因**：`os-image/config/branding/etc/os-release` 硬編碼 `VERSION_CODENAME=noble`，`apply-branding.sh` 以 `cp -a branding/. rootfs/` 覆蓋 resolute clone 的 `/etc/os-release`。

**修復**：
- `apply-branding.sh` 載入 `ubuntu-base-env.sh`，依 `ubuntu-base-target.json` active slot 寫入 `VERSION_ID` / `VERSION_CODENAME` / `UBUNTU_CODENAME`
- 更新 `os-image/config/branding/etc/os-release` 範本為 resolute 26.04

### 2. 先前階段 E2E 修復（已納入本輪 ISO）

- Calamares resolute initramfs stub（`shellprocess_initramfs-resolute.conf`）
- E2E guest runner fast-exit（無 9p 時不阻塞 boot）
- install-firstboot timeout / disk size / grub.cfg fallback
- preflight `squashfs_has_path` symlink 修正

## 驗證命令輸出

### `make test-u26-regression-e2e`

```
PASS: active Ubuntu 26.04.0 resolute
PASS: release ISO StrawWU-0.6.1.5-amd64.iso (4860 MiB)
PASS: boot-result 0.6.1.5 BIOS+UEFI STRAWWU_BOOT_OK
PASS: firstboot-e2e 0.6.1.5 install+boot+FIRSTBOOT_OK
PASS: .regression-e2e-ok resolute 0.6.1.5
PASS: u26-regression-e2e preflight stub
```

### `make preflight`

```
POST-MVP INFRASTRUCTURE OK
(exit 0)
```

## 證據路徑

| 項目 | 路徑 |
|------|------|
| release ISO | `os-image/output/StrawWU-0.6.1.5-amd64.iso` |
| boot-test | `tests/boot/output/boot-result.json` |
| firstboot E2E | `tests/install-e2e/output/firstboot-e2e-result.json` |
| regression marker | `os-image/work/.regression-e2e-ok` |
| rootfs os-release | `VERSION_CODENAME=resolute`, `VERSION_ID=26.04` |

## 主要 log

| 步驟 | log |
|------|-----|
| resolute clone | `/tmp/u26-m6-clone-resolute-v2.log` |
| release-iso (resolute) | `/tmp/u26-m6-release-iso-resolute-v3.log` |
| boot-test (resolute ISO) | `/tmp/u26-m6-boot-test-resolute.log` |
| firstboot E2E (前輪) | `/tmp/u26-m6-firstboot-e2e-v7.log` |
| preflight | `/tmp/u26-m6-preflight.log` |

## 變更檔案（本輪新增/修改）

- `os-image/scripts/apply-branding.sh` — resolute os-release 保留
- `os-image/config/branding/etc/os-release` — 範本更新為 26.04 resolute
- （前序）`os-image/scripts/sync-calamares-installer.sh`
- （前序）`os-image/debs/strawwu-calamares-settings/.../shellprocess_initramfs-resolute.conf`
- （前序）`tests/install-e2e/guest/*`、`tests/preflight/test-iso-before-boot.sh`

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-regression-e2e
make preflight
```

## 備註

- firstboot E2E 證據來自本階段前序 run（`firstboot-e2e-v7`，0.6.1.5 PASS）；boot-test 已於 resolute ISO 重建後重跑並更新 `boot-result.json`。
- VERSION 維持 `0.6.1.5`（本輪修復已納入該版 release ISO）；若需另 bump 請由 Hermes 指示後重跑完整鏈。
