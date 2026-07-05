# W5-I3 Target Identity 階段報告

| 任務 | w5-i3-target-identity |
|------|------------------------|
| 版本 | 0.4.1.28 |
| 日期 | 2026-07-05 |
| Worker | 階段 26/47（w5-i3-target-identity） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

安裝後身份：Calamares chroot 內套用 GRUB 選單標題、Plymouth 主題、initramfs/grub 刷新，以及 issue/motd 使用者可見字串（LEG3）。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-target-identity/` |
| CLI | `/usr/bin/strawwu-target-identity` |
| 核心邏輯 | `usr/lib/strawwu-target-identity/core.py` |
| GRUB drop-in | `etc/default/grub.d/99-strawwu-identity.cfg` |
| Manifest | `usr/share/strawwu/target-identity/target-identity-manifest.yaml` |
| Calamares hook | `shellprocess_target-identity.conf`（chroot，`dontChroot: false`） |
| grubcfg 預設 | `grubcfg.conf` 新增 `GRUB_DISTRIBUTOR: "StrawWU"` |
| settings 整合 | exec：`target_setup` → `target_identity` → `install_marker` |
| target 合流 | `target-manifest.yaml`、`install-init-manifest.yaml` |
| chroot 建置 | `chroot-install-target-setup.sh` 納入 identity deb + 驗證 |
| Preflight | `tests/preflight/test-target-identity.sh` |
| baseline | `docs/plans/baselines/target-identity-baseline.json` |
| Makefile | `test-target-identity`；`preflight` 含本階段 |
| Observability | `strawwu-observability-debug-plan.md` 新增 `target-identity.log` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| GRUB | `/etc/default/grub.d/99-strawwu-identity.cfg` + 修補 `/etc/default/grub`；`update-grub` |
| Calamares grubcfg | 預設 `GRUB_DISTRIBUTOR: "StrawWU"`（與 `bootloader.conf` efiBootloaderId 對齊） |
| Plymouth | `update-alternatives` + `plymouth-set-default-theme strawwu-boot`；`plymouthd.conf` Theme |
| initramfs | `update-initramfs -u`（Calamares 路徑；chroot 模擬用 `--skip-initramfs`） |
| 使用者可見字串 | `/etc/issue`、`issue.net`、`motd` 中 Ubuntu → StrawWU |
| 生命週期 | `strawwu-initd set lifecycle.target_identity running→done` |
| 標記 | `/var/lib/strawwu/setup/target-identity.ok` |
| 錯誤碼 | `SWU-IN-003` |
| 日誌 | 結構化 JSON → `/var/log/strawwu/target-identity.log` |

## 驗收命令輸出

### 2026-07-05T09:34–09:36 UTC-4（companion check 終驗）

#### `make test-target-identity` — exit 0（~0.8s）

Log: `/tmp/w5-i3-test-target-identity-worker.log`

```
=== W5-I3 target-identity done: PASS ===
```

關鍵檢查項：deb 結構、grubcfg/bootloader 預設、Calamares shellprocess 時序、5 項單元測試 PASS、CLI dry-run、`strawwu-target-identity_0.4.1.28_all.deb`（9.4K）、rootfs grub drop-in + CLI 存在。squashfs 有 WARN（不阻斷）。

#### `make preflight` — exit 0（~112s）

Log: `/tmp/w5-i3-preflight-worker.log`

含 W0 baseline + W1–W4 全部階段 + W5-N3/N4/D4/R4 + **W5-I3 target-identity** 全部 exit 0。

### 2026-07-05T09:19–09:22 UTC-4（worker 初終驗，同上結果）

### chroot 同步

Log: `/tmp/w5-i3-chroot-target-setup.log`（部分）、手動 chroot 驗證

| 項目 | 結果 |
|------|------|
| rootfs CLI | `/usr/bin/strawwu-target-identity` 存在 |
| rootfs GRUB | `99-strawwu-identity.cfg` 含 `GRUB_DISTRIBUTOR="StrawWU"` |
| rootfs Calamares | `shellprocess_target-identity.conf` 已安裝 |
| squashfs | CLI/grub drop-in 需完整 chroot rsync（preflight WARN，不阻斷 PASS） |

**備註**：在已配置 rootfs 上重跑 `chroot-install-target-setup.sh` 時，`strawwu-target-setup --calamares-chroot` 可能回傳 rc=1（重複安裝）；全新 Calamares 安裝路徑不受影響。release-iso 重打包後 squashfs 會同步。

## 技術備註（治本）

1. **時序**：`target_identity` 在 `target_setup`（staged debs）之後、`install_marker` 之前，確保 GRUB/Plymouth 在 chroot 內最終刷新。
2. **雙層 GRUB**：Calamares `grubcfg` 模組預設 + target-identity drop-in，避免上游 Ubuntu distributor 回歸。
3. **Plymouth 依賴 live branding**：主題檔由 `apply-branding.sh` 寫入 squashfs；target-identity 負責 alternatives/initramfs 啟用。
4. **乾淨室**：未複製 legacy；邏輯對齊 `apply-branding.sh` chroot 段與 LEG3 合規計畫。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 已安裝系統 boot E2E | 待 W6-I4 |
| install E2E serial marker | 待 W6-N5 |
| LEG3 完整合規 gate | 待 LEG4 CI |
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |
| ubuntu-desktop 全面替換 | 待 W5-B4 |

## 變更檔案清單

```
VERSION (0.4.1.27 → 0.4.1.28)
Makefile
os-image/debs/strawwu-target-identity/                         (新增)
os-image/debs/strawwu-calamares-settings/etc/calamares/        (grubcfg, settings, shellprocess)
os-image/config/calamares-installer/etc/calamares/             (同步)
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/debs/strawwu-install-init/usr/share/strawwu/install-init/install-init-manifest.yaml
os-image/debs/strawwu-target-setup/tests/test-target-setup.py
os-image/scripts/chroot-install-target-setup.sh
tests/preflight/test-target-identity.sh                        (新增)
docs/plans/baselines/target-identity-baseline.json             (新增)
docs/plans/strawwu-observability-debug-plan.md
docs/plans/stage-reports/W5-I3-target-identity-report.md       (本檔)
```

## VERSION

`0.4.1.27` → `0.4.1.28`（iterate）

## 建議 commit message

```
feat(w5): add strawwu-target-identity GRUB/Plymouth post-install hook

- Calamares shellprocess@target_identity after target_setup
- GRUB_DISTRIBUTOR drop-in, Plymouth strawwu-boot, initramfs refresh
- target-manifest + install-init-manifest + preflight test-target-identity
Tests: make test-target-identity PASS, make preflight PASS
Version: 0.4.1.28
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T09:04:16-0400 | `[worker-TICK]` w5-r4 PASS → w5-i3 launched |
| 2026-07-05T09:11:00-0400 | worker 初驗完成 |
| 2026-07-05T09:19:07-0400 | `[worker-TICK]` periodic companion check status=IN_PROGRESS |
| 2026-07-05T09:22:00-0400 | worker 初終驗完成 |
| 2026-07-05T09:34:07-0400 | `[worker-TICK]` periodic companion check status=IN_PROGRESS |
| 2026-07-05T09:36:00-0400 | companion check 終驗完成 — 待 Hermes mark PASS |

## 下一步

**w5-b4-disable-upstream-init**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-target-identity
make preflight
# 可選（需 root + 既有 rootfs）：
# bash os-image/scripts/chroot-install-target-setup.sh
```
