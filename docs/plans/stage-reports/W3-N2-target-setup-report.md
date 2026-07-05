# W3-N2 Target Setup 階段報告

| 任務 | w3-n2-target-setup |
|------|---------------------|
| 版本 | 0.4.1.13 |
| 日期 | 2026-07-05 |
| Worker | 階段 14/47（w3-n2-target-setup） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| Companion | `[worker-TICK]` 2026-07-05T05:18:44-0400 status=IN_PROGRESS → 終驗完成 |

## 目標

Calamares chroot hook：`strawwu-target-setup` 在安裝 exec 階段於 target chroot 內初始化 state、安裝 staged StrawWU debs、寫入 lifecycle。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-target-setup/` |
| CLI | `os-image/debs/strawwu-target-setup/usr/bin/strawwu-target-setup` |
| 核心邏輯 | `os-image/debs/strawwu-target-setup/usr/lib/strawwu-target-setup/core.py` |
| 安裝 manifest | `os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml` |
| Calamares hook | `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/shellprocess_target-setup.conf` |
| settings 整合 | `settings.conf` exec：`packages` → `shellprocess@target_setup` → `install_marker` |
| E2E 同步 | `os-image/config/calamares-installer/` 同上 |
| 單元測試 | `os-image/debs/strawwu-target-setup/tests/test-target-setup.py` |
| chroot 安裝 | `os-image/scripts/chroot-install-target-setup.sh` |
| Preflight | `tests/preflight/test-target-setup.sh` |
| baseline | `docs/plans/baselines/target-setup-baseline.json` |
| Makefile | `test-target-setup`、`install-target-setup`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| Calamares chroot | `dontChroot: false` → `/usr/bin/strawwu-target-setup --calamares-chroot` |
| state 整合 | 呼叫 `strawwu-initd init`；`lifecycle.install=installed`；`target_setup running→done` |
| staged debs | `/usr/share/strawwu/target-setup/staged-debs/*.deb` + `target-manifest.yaml` 順序安裝 |
| 安裝範圍 | initd · session · update-notifier · bug-reporter · flatpak-setup · desktop |
| 日誌 | 結構化 JSON → `/var/log/strawwu/target-setup.log` |
| 錯誤碼 | 失敗記錄 `SWU-IN-002` |
| rescue | `--repair-only`（對齊 upgrade-recovery plan） |
| GDM | 設定 `DefaultSession=strawwu-session`（若 gdm3 存在） |
| boot-selfcheck | enable systemd unit（若存在） |
| Live ISO 過渡 | chroot 腳本保留 `ubuntu-minimal`/`ubuntu-desktop-minimal`/`ubuntu-desktop` 至 W5-B4；重 purge  telemetry |

## 驗收命令輸出（2026-07-05T05:19 UTC-4，worker 終驗）

### `make test-target-setup` — exit 0（~0.8s）

Log: `/tmp/w3-n2-test-target-setup.log`

```
=== W3-N2 target-setup done: PASS ===
```

關鍵檢查項：6 項單元測試 PASS、`strawwu-target-setup_0.4.1.13_all.deb`（~9.6K）、Calamares hook 在 rootfs+squashfs、chroot marker 存在、desktop stack 已安裝。

### `make preflight` — exit 0（~36s）

Log: `/tmp/w3-n2-preflight.log`

含 W0 baseline + W1-B1~F2 + W2-N1/B2/I1/R1/trust + W3-D1/I2/B3 + **W3-N2 target-setup** 全部 exit 0。

### chroot 安裝

Log: `/tmp/w3-n2-chroot-install.log`

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.target-setup-ok` 存在 |
| rootfs | strawwu-target-setup · initd · session · desktop · update-notifier installed |
| squashfs | calamares hook + strawwu-install.desktop synced |
| state | `lifecycle.target_setup=done` |

## 技術備註（治本）

1. **避免 apt-get install -f**：批次 `dpkg -i` + `apt-get -f` 會誤刪 `ubuntu-minimal`/`ubuntu-desktop`（Live ISO 過渡期仍需要）；改為逐包 `dpkg -i`，meta 用 `--force-depends`。
2. **Calamares 時序**：target-setup 在 `packages` 之後、`install_marker` 之前於 chroot 執行，符合 install-init 生命週期。
3. **staged debs**：Live squashfs 預先 stage deb 檔，Calamares 安裝到磁碟時 chroot 內可直接 `dpkg -i`，無需網路。
4. **telemetry 回歸防護**：過渡 meta 還原後以 `dpkg --purge --force-all` 重 purge apport 等套件，維持 W1-B1 baseline。
5. **乾淨室實作**：未複製 legacy hook；整合既有 `strawwu-initd` state CLI。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| `strawwu-install-init` deb | 待 W3+ / W5 |
| `strawwu-firstboot` deb | 待 W5-N3 |
| ubuntu-desktop 全面替換 | 待 W5-B4 |
| target identity GRUB/Plymouth | 待 W5-I3 |
| install E2E serial marker | 待 W6-N5 |
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |

## 變更檔案清單

```
VERSION (0.4.1.12 → 0.4.1.13)
Makefile
os-image/debs/strawwu-target-setup/                         (新增)
os-image/debs/strawwu-calamares-settings/etc/calamares/     (target_setup hook)
os-image/config/calamares-installer/etc/calamares/        (同步)
os-image/scripts/chroot-install-target-setup.sh             (新增)
tests/preflight/test-target-setup.sh                        (新增)
docs/plans/baselines/target-setup-baseline.json             (新增)
docs/plans/stage-reports/W3-N2-target-setup-report.md       (本檔)
```

## VERSION

`0.4.1.12` → `0.4.1.13`（iterate）

## 建議 commit message

```
feat(w3): add strawwu-target-setup Calamares chroot hook

- shellprocess@target_setup runs in chroot after packages module
- Staged deb manifest + strawwu-initd lifecycle integration
- chroot-install-target-setup + test-target-setup preflight
Tests: make test-target-setup PASS, make preflight PASS
Version: 0.4.1.13
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T05:03:44-0400 | `[worker-TICK]` companion check IN_PROGRESS（前次 worker） |
| 2026-07-05T05:04:47-0400 | `[worker-DONE]` 前次終驗完成 |
| 2026-07-05T05:18:44-0400 | `[worker-TICK]` companion check IN_PROGRESS（本 worker） |
| 2026-07-05T05:19:30-0400 | `[worker-DONE]` 本 worker 終驗完成 — 待 Hermes mark PASS |

## 下一步

**w3-w0-wincompat-baseline**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-target-setup
make preflight
# 可選（需 root + 既有 rootfs）：
# bash os-image/scripts/chroot-install-target-setup.sh
```
