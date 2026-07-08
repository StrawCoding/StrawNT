# POST-I2 Calamares LUKS + 雙系統 — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-i2-calamares-luks` |
| 版本 | `0.6.3.8`（`0.6.3.7` → `0.6.3.8` preflight output-dir race fix） |
| 版本目標 | `0.6.0.0-target` |
| 對照 | C7 LUKS、C8 雙系統偵測 |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T08:16+08:00（worker 階段 1/8，tick461/462 修復重跑） |

## 摘要

完成 Post-MVP I2 **Calamares LUKS 加密 + 雙系統偵測 UX**：`strawwu-calamares-settings` 啟用 LUKS1 自動加密、GRUB cryptodisk、os-prober 雙啟動選單；新增 `strawwu-dualboot-detect.sh` exec 階段探測腳本、PartitionPage 繁中文案、install-e2e scenario marker，以及 POST-I2 preflight gate。

**Hermes tick461/462 修復**：preflight 並行執行時 `test-finished-meta.sh` / `test-firstboot.sh` 的 `rm -rf output/` 與 `mktemp "${DEB_FILE}.XXXXXX")` 競態，導致 install-init / firstboot deb 建置失敗。改為在 `/tmp` 建暫存 deb，再 `mkdir -p output && mv` 原子寫入。

## 交付物

| 類型 | 路徑 |
|------|------|
| LUKS partition | `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/partition.conf` |
| GRUB cryptodisk + os-prober | `.../modules/grubcfg.conf` |
| 雙系統偵測 | `.../usr/local/lib/calamares/strawwu-dualboot-detect.sh` |
| exec 接線 | `.../modules/shellprocess_dualboot-detect.conf`、`settings.conf` |
| 繁中 UX | `.../usr/share/calamares/lang/calamares_zh_TW.ts` |
| LUKS scenario | `tests/install-e2e/scenarios/luks-scenario.marker.json` |
| Dualboot scenario | `tests/install-e2e/scenarios/dualboot-scenario.marker.json` |
| 靜態驗證 | `tests/install-e2e/validate-luks-dualboot-scenarios.sh` |
| Preflight | `tests/preflight/test-calamares-luks-dualboot.sh` |
| 單元測試 | `os-image/debs/strawwu-calamares-settings/tests/test-luks-dualboot.py` |
| Baseline | `docs/plans/baselines/calamares-luks-dualboot-baseline.json` |
| 進階計畫 | `docs/plans/strawwu-installer-advanced-plan.md` v1.1 |

## C7 / C8 對照

| 維度 | 實作 |
|------|------|
| C7 LUKS | `luksGeneration: luks1`、`enableLuksAutomatedPartitioning: true`、`GRUB_ENABLE_CRYPTODISK: true`、`crypttabOptions: luks` |
| C8 雙系統 | `initialPartitioningChoice: none`、`requiredStorage: 8`、`GRUB_DISABLE_OS_PROBER: false`、`os-prober` 偵測腳本 + 繁中 alongside 文案 |

**install-e2e 例外**：guest `e2e-bootloader-setup.sh` 維持 `GRUB_DISABLE_OS_PROBER=true`（headless determinism）；production calamares-settings 啟用 os-prober。

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.7` → `0.6.3.8` |
| `os-image/debs/strawwu-calamares-settings/build-deb.sh` | deb 建置改 `/tmp` 暫存 + 原子 mv（race-safe） |
| `os-image/debs/strawwu-install-init/build-deb.sh` | 同上（tick461 install-init output dir 根因） |
| `os-image/debs/strawwu-firstboot/build-deb.sh` | 同上（tick462 firstboot output dir 根因） |
| `os-image/debs/strawwu-calamares-settings/tests/test-l10n-finished.py` | lrelease 改 temp dir，避免 preflight 競態 |
| `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/partition.conf` | LUKS + dual-boot choice |
| `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/grubcfg.conf` | cryptodisk + os-prober |
| `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/welcome.conf` | requiredStorage |
| `os-image/debs/strawwu-calamares-settings/etc/calamares/settings.conf` | dualboot_detect exec |
| `os-image/debs/strawwu-calamares-settings/usr/local/lib/calamares/strawwu-dualboot-detect.sh` | **新增** |
| `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/shellprocess_dualboot-detect.conf` | **新增** |
| `os-image/debs/strawwu-calamares-settings/usr/share/calamares/lang/calamares_zh_TW.ts` | PartitionPage 文案 |
| `os-image/debs/strawwu-calamares-settings/tests/test-luks-dualboot.py` | **新增** 8 項單元測試 |
| `os-image/config/calamares-installer/etc/calamares/modules/partition.conf` | 同步 LUKS 設定 |
| `tests/install-e2e/scenarios/*.marker.json` | **新增** luks / dualboot markers |
| `tests/install-e2e/validate-luks-dualboot-scenarios.sh` | **新增** |
| `tests/preflight/test-calamares-luks-dualboot.sh` | **擴充** 完整 gate |
| `docs/plans/baselines/calamares-luks-dualboot-baseline.json` | **新增** |
| `docs/plans/strawwu-installer-advanced-plan.md` | v1.1 實作細節 |

## 驗證命令輸出

### `make test-calamares-luks-dualboot` — exit 0（~0.6s，2026-07-08T08:12+08:00）

Log: `/tmp/post-i2-test-calamares-luks-dualboot.log`

```
=== POST-I2 calamares LUKS/dualboot preflight ===
PASS: partition.conf LUKS automated encryption (C7)
PASS: partition.conf dual-boot choice page (no pre-selected erase)
PASS: grubcfg cryptodisk + os-prober enabled (C7/C8)
PASS: install-e2e LUKS/dualboot scenario markers
PASS: strawwu-calamares-settings luks-dualboot unit tests (8/8)
PASS: build-deb.sh succeeded
PASS: deb artifact strawwu-calamares-settings_0.6.3.8_all.deb
=== POST-I2 calamares LUKS/dualboot done: PASS ===
```

### `make preflight` — exit 0（~240s，2026-07-08T08:16+08:00）

Log: `/tmp/post-i2-preflight.log`（1823 PASS，`grep FAIL:` **0** 行）

含 W5-N3 firstboot、W5-N4 finished-meta（install-init deb 建置）、W0–W8 MVP + POST-HW + fork/U26 closeout 全鏈 PASS。

**tick461 根因**：`mktemp "${OUTPUT_DIR}/...deb.XXXXXX")` 時 output 目錄被並行 preflight 的 `rm -rf output/` 刪除 → `No such file or directory`。

**tick462 根因**：`strawwu-firstboot` 直接 `dpkg-deb --build ... output/...deb`，同樣遭遇 output 目錄競態刪除。

**修復**：三個 `build-deb.sh` 改 `/tmp/strawwu-*_${VERSION}.XXXXXX.deb` 暫存建置，`mkdir -p output` 後 `mv -f` 原子寫入。

## 已知限制 / Hermes 建議驗收

| 項目 | 狀態 |
|------|------|
| QEMU 全路徑 LUKS install E2E | 未在本 worker 執行（需 passphrase/keyscript 注入 + release-iso rebuild） |
| chroot 安裝新 deb | marker 缺失 WARN — 需 `sudo bash os-image/scripts/chroot-install-calamares-settings.sh` + `dev-iso`/`release-iso` |
| 實機 alongside Windows | 建議 Hermes 實機或 preseeded 磁碟驗收 os-prober + GRUB 選單 |

## 建議 Hermes 後續

1. `sudo bash os-image/scripts/chroot-install-calamares-settings.sh` → `make release-iso`
2. 實機或 QEMU 預填 NTFS 分割區 → 驗證 alongside + os-prober 文案
3. LUKS 安裝 → 重開機解鎖 → `STRAWWU_BOOT_OK`
4. mark PASS → 自動啟動 `post-d7-software-sources`

## Commit message（建議）

```
fix(post-i2): race-safe deb build for preflight parallel output/ cleanup

- Build calamares-settings, install-init, firstboot debs in /tmp then atomic mv
- Resolves Hermes tick461/462 preflight FAIL on install-init output dir
Tests: make test-calamares-luks-dualboot PASS; make preflight PASS (1823 checks)
Version: 0.6.3.8
Stage: post-i2-calamares-luks
```
