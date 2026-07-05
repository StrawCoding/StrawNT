# W3-B3 Update Notifier 階段報告

| 任務 | w3-b3-update-notifier |
|------|------------------------|
| 版本 | 0.4.1.12 |
| 日期 | 2026-07-05 |
| Worker | 階段 13/47（w3-b3-update-notifier） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

取代 Ubuntu `update-notifier`，提供 StrawWU 品牌更新通知與升級前備份提醒（v0.5 文案 only）。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-update-notifier/` |
| CLI | `os-image/debs/strawwu-update-notifier/usr/bin/strawwu-update-notifier` |
| 核心邏輯 | `os-image/debs/strawwu-update-notifier/usr/lib/strawwu-update-notifier/core.py` |
| APT pre-upgrade hook | `os-image/debs/strawwu-update-notifier/usr/lib/strawwu-update-notifier/apt-pre-upgrade` |
| APT 設定 | `os-image/debs/strawwu-update-notifier/etc/apt/apt.conf.d/99strawwu-update-notifier` |
| 備份文案 | `os-image/debs/strawwu-update-notifier/usr/share/strawwu/update-notifier/backup-copy.yaml` |
| 自動啟動 | `os-image/debs/strawwu-update-notifier/usr/share/applications/strawwu-update-notifier.desktop` |
| 單元測試 | `os-image/debs/strawwu-update-notifier/tests/test-update-notifier.py` |
| chroot 安裝 | `os-image/scripts/chroot-install-update-notifier.sh` |
| Preflight | `tests/preflight/test-update-notifier.sh` |
| baseline | `docs/plans/baselines/update-notifier-baseline.json` |
| Makefile | `test-update-notifier`、`install-update-notifier`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 取代 update-notifier | `Provides/Conflicts/Replaces: update-notifier`；chroot 已 purge 上游套件 |
| 更新檢查 | `strawwu-update-notifier check` / `notify`（apt dist-upgrade 模擬） |
| 升級前備份提醒 | `pre-upgrade` 子命令 + APT `DPkg::Pre-Install-Pkgs` hook（文案 only） |
| 多語文案 | `backup-copy.yaml` 含 en / zh_TW；繁中標題「升級前請先備份」 |
| 日誌 | 結構化 JSON 寫入 `/var/log/strawwu/update.log` |
| 錯誤碼 | 預留 `SWU-UP-005` rollback 記錄 API（`log_rollback()`） |
| 自動啟動 | GNOME session `strawwu-update-notifier.desktop` → `notify` |
| 商標合規 | 文案與 desktop 無 Ubuntu 字樣 |

## 驗收命令輸出（2026-07-05T04:46 UTC-4，worker 複驗）

### `make test-update-notifier` — exit 0（~5s）

Log: `/tmp/w3-b3-test-update-notifier.log`

```
=== W3-B3 update-notifier done: PASS ===
```

關鍵檢查項：6 項單元測試 PASS、`strawwu-update-notifier_0.4.1.12_all.deb`（12K）、Provides/Conflicts update-notifier、rootfs+squashfs 已安裝且上游 update-notifier absent、chroot marker 存在。

### `make preflight` — exit 0（~43s）

Log: `/tmp/w3-b3-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-N1 init-tools + W2-B2 bug-reporter + W2-I1 calamares-settings + W2-R1 app-registry + W2-trust SEC2/OBS1/LEG2 + W3-D1 desktop-stack + W3-I2 live-install-ux + **W3-B3 update-notifier** 全部 exit 0。

### chroot 安裝

Log: `/tmp/w3-b3-chroot-install.log`

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.update-notifier-ok` 存在 |
| deb | `strawwu-update-notifier_0.4.1.12_all.deb`（~12K） |
| rootfs CLI | `/usr/bin/strawwu-update-notifier` 可執行 |
| 上游替換 | `update-notifier` purged；`strawwu-update-notifier` installed |
| APT hook | `/etc/apt/apt.conf.d/99strawwu-update-notifier` 存在 |

## 技術備註（治本）

1. **虛擬套件替換**：以 `Provides: update-notifier` 滿足 `update-manager` / `ubuntu-desktop` 依賴，無需 patch 上游 meta（W5-B4 再全面替換 ubuntu-desktop）。
2. **備份提醒範圍**：依 `strawwu-deferred-scope.md`，v0.5 僅文案；`strawwu-backup` GUI/排程延後 v1.0。
3. **APT hook 時機**：`DPkg::Pre-Install-Pkgs` 僅在有 stdin 套件清單時觸發，避免 chroot 空跑；headless 環境 fallback 至 stderr + notify-send。
4. **update-notifier-common 保留**：server 共用檔仍留上游；僅 GUI `update-notifier` 被替換。
5. **乾淨室實作**：未複製 Ubuntu update-notifier 源碼；自研 Python3 + apt/notify-send/zenity 整合。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| strawwu-desktop Depends update-notifier 替換 | 待 W3-N2 target-setup / W5-B4 meta audit |
| update-manager snapd-glib 依賴 | 仍保留 libsnapd-glib（W1-F2 已文件化） |
| strawwu-upgrade CLI / snapshot rollback | 待 UPG1–UPG5 |
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |
| zenity 備份對話框 | Recommends zenity；無 GUI 時 fallback notify-send |

## 變更檔案清單

```
VERSION (0.4.1.11 → 0.4.1.12)
Makefile
os-image/debs/strawwu-update-notifier/                    (新增)
os-image/scripts/chroot-install-update-notifier.sh        (新增)
tests/preflight/test-update-notifier.sh                   (新增)
docs/plans/baselines/update-notifier-baseline.json       (新增)
docs/plans/stage-reports/W3-B3-update-notifier-report.md (本檔)
```

## VERSION

`0.4.1.11` → `0.4.1.12`（iterate）

## 建議 commit message

```
feat(w3): add strawwu-update-notifier replacing update-notifier

- Provides update-notifier for update-manager/ubuntu-desktop deps
- Pre-upgrade backup reminder (en/zh_TW copy, text only)
- APT Pre-Install-Pkgs hook + session autostart notify
- chroot install hook + preflight test-update-notifier
Tests: make test-update-notifier PASS, make preflight PASS
Version: 0.4.1.12
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| （待填） | `[worker-PASS]` / `[worker-DONE]` |

## 下一步

**w3-n2-target-setup**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-update-notifier
make preflight
```
