# StrawWU 安裝器進階（LUKS + 雙系統）

| 版本 | 1.1 |
|------|-----|
| 對照維度 | C7 LUKS、C8 雙系統偵測 |
| Stage | `post-i2-calamares-luks` |
| StrawWU 版本 | 0.6.3.7 |

## 目標

1. Calamares LUKS 全碟/分割加密路徑獨立 E2E（QEMU 或實機）
2. 雙啟動（Windows/macOS 共存）偵測與使用者文案（strawwu-calamares-settings）
3. `tests/install-e2e/` 新增 luks / dualboot scenario marker

## C7 — LUKS 加密

| 元件 | 設定 |
|------|------|
| `partition.conf` | `luksGeneration: luks1`、`enableLuksAutomatedPartitioning: true` |
| `grubcfg.conf` | `GRUB_ENABLE_CRYPTODISK: true` |
| `fstab.conf` | `crypttabOptions: luks,keyscript=/bin/cat` |
| initramfs | `shellprocess_initramfs-resolute` → `update-initramfs`（含 cryptsetup hook） |

LUKS1 選用原因：GRUB 原生支援 LUKS1 開機解鎖；與 W6-I4 hybrid BIOS+UEFI 布局相容。

## C8 — 雙系統偵測與 UX

| 元件 | 行為 |
|------|------|
| `partition.conf` | `initialPartitioningChoice: none` — 使用者必須選擇 erase/replace/**alongside** |
| `welcome.conf` | `requiredStorage: 8` GiB — 啟用 replace/alongside 路徑 |
| `grubcfg.conf` | `GRUB_DISABLE_OS_PROBER: false` — 安裝後 GRUB 顯示其他 OS |
| `strawwu-dualboot-detect.sh` | exec 階段 `os-prober` 記錄至 `/var/log/strawwu-dualboot-detect.log` |
| `calamares_zh_TW.ts` | PartitionPage：並存安裝、LUKS 加密、已偵測 OS 文案 |

**install-e2e 例外**：guest `e2e-bootloader-setup.sh` 仍設 `GRUB_DISABLE_OS_PROBER=true` 以確保 headless 開機 determinism；production ISO 使用 calamares-settings 預設（os-prober 啟用）。

## install-e2e scenario markers

| Scenario | Marker | 路徑 |
|----------|--------|------|
| luks | `STRAWWU-LUKS-SCENARIO-OK` | `tests/install-e2e/scenarios/luks-scenario.marker.json` |
| dualboot | `STRAWWU-DUALBOOT-SCENARIO-OK` | `tests/install-e2e/scenarios/dualboot-scenario.marker.json` |

靜態驗證：`tests/install-e2e/validate-luks-dualboot-scenarios.sh`

完整 QEMU LUKS 安裝 E2E 留待 Hermes `release-iso` boot-test 觸發（需 passphrase 互動或 keyscript 注入）。

## 驗收

```bash
make test-calamares-luks-dualboot
make preflight
```

Stage report：`docs/plans/stage-reports/POST-I2-calamares-luks-report.md`

## 後續

- Hermes mark PASS → 自動啟動 `post-d7-software-sources`
- 建議 Hermes 觸發 release-iso + 實機 LUKS / 雙系統 alongside 驗收
