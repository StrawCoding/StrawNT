# W3-I2 Live 安裝 UX 階段報告

| 任務 | w3-i2-live-ux |
|------|---------------|
| 版本 | 0.4.1.11 |
| 日期 | 2026-07-05 |
| Worker | 階段 12/47（w3-i2-live-ux） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

strawwu-install.desktop + Calamares finished 文案：Live 環境提供 StrawWU 品牌安裝捷徑，並定義完成頁文案與重新開機行為。

## 交付物

| 類型 | 路徑 |
|------|------|
| Live UX deb | `os-image/debs/strawwu-live-install-ux/` |
| 安裝捷徑 | `os-image/debs/strawwu-live-install-ux/usr/share/applications/strawwu-install.desktop` |
| finished 文案基線 | `os-image/debs/strawwu-live-install-ux/usr/share/strawwu/installer/finished-copy.yaml` |
| finished 模組設定 | `os-image/debs/strawwu-calamares-settings/etc/calamares/modules/finished.conf`（更新） |
| 單元測試 | `os-image/debs/strawwu-live-install-ux/tests/test-live-install-ux.py` |
| Preflight | `tests/preflight/test-live-install-ux.sh` |
| baseline | `docs/plans/baselines/live-install-ux-baseline.json` |
| Makefile | `test-live-install-ux`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| strawwu-install.desktop | `Install StrawWU` / `安裝 StrawWU`；Icon=`distributor-logo`；Exec=`sudo -E calamares -D6` |
| 隱藏上游入口 | postinst 將 `calamares.desktop` 設 `Hidden=true`（保留二進位，僅隱藏選單） |
| finished.conf | `restartNowMode: user-checked`、`notifyOnFinished: true`、`systemctl -i reboot` |
| finished 文案 | `finished-copy.yaml` 定義 zh_TW/en 成功/失敗/Live 提示（Calamares UI 透過 branding `versionedName` 渲染；本檔為 canonical 參考） |
| 商標合規 | desktop 與 finished-copy 無 Ubuntu 字樣 |
| deb 依賴 | `strawwu-live-install-ux` Depends `calamares` + `strawwu-calamares-settings` |

## 驗收命令輸出（2026-07-05T04:29 UTC-4，worker 複驗）

### `make test-live-install-ux` — exit 0（~0.5s）

Log: `/tmp/w3-i2-test-live-install-ux.log`

```
=== W3-I2 live-install-ux done: PASS ===
```

關鍵檢查項：desktop 品牌/繁中名稱、finished-copy zh_TW、finished.conf notify+restart、5 項單元測試 PASS、`strawwu-live-install-ux_0.4.1.11_all.deb`（2.2K）、calamares-settings deb 含更新 finished.conf。

### `make preflight` — exit 0（~30s）

Log: `/tmp/w3-i2-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-N1 init-tools + W2-B2 bug-reporter + W2-I1 calamares-settings + W2-R1 app-registry + W2-trust SEC2/OBS1/LEG2 + W3-D1 desktop-stack + **W3-I2 live-install-ux** 全部 exit 0。

WARN（預期）：squashfs 尚未 chroot 安裝 `strawwu-live-install-ux` deb；`strawwu-install.desktop` 不在 squashfs 內，待 W3-N2 target-setup 或 ISO 重打包整合。

## 技術備註（治本）

1. **桌面入口與設定分離**：`strawwu-live-install-ux` 負責 Live 選單 UX；`finished.conf` 仍由 `strawwu-calamares-settings` 擁有（避免 dpkg 檔案衝突）。
2. **Calamares finished 文案機制**：Calamares 3.3.5 finished 頁主文由 `branding.versionedName` + l10n 模板渲染；`finished-copy.yaml` 提供 zh_TW canonical 文案供 UX/法務審核，後續 W5-N4 可接 calamares `.qm` 覆寫。
3. **Live 重新開機 UX**：`user-checked` + `notifyOnFinished` 對齊 Live USB 試用→安裝→可選重開機流程（PRD v0.5）。
4. **ISO 整合待後續**：squashfs 尚未 chroot 安裝本 deb；W3-N2 target-setup 或 ISO 重打包時一併納入。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| squashfs 安裝 live-install-ux deb | 未打包；需 chroot install |
| calamares zh_TW .qm 覆寫 | 待 W5-N4 finished-meta |
| target identity / firstboot | 待 W5-I3、W5-N3 |
| release-iso 重打包 | chroot 變更後需 `make dev-iso`/`release-iso` |

## 變更檔案清單

```
VERSION (0.4.1.10 → 0.4.1.11)
Makefile
os-image/debs/strawwu-live-install-ux/                    (新增)
os-image/debs/strawwu-calamares-settings/etc/calamares/modules/finished.conf
tests/preflight/test-live-install-ux.sh                 (新增)
docs/plans/baselines/live-install-ux-baseline.json      (新增)
docs/plans/stage-reports/W3-I2-live-ux-report.md        (新增)
```

## VERSION

`0.4.1.10` → `0.4.1.11`（iterate）

## 建議 commit message

```
feat(w3): add strawwu-install.desktop and finished-page copy baseline

- strawwu-live-install-ux deb with branded desktop + finished-copy.yaml
- finished.conf: notifyOnFinished + user-checked reboot for Live UX
- test-live-install-ux preflight + live-install-ux-baseline.json
Tests: make test-live-install-ux PASS, make preflight PASS
Version: 0.4.1.11
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T04:17:00-0400 | `[worker-DONE]` 初版實作完成 |
| 2026-07-05T04:18:00-0400 | `[worker-DONE]` 複驗 test-live-install-ux + preflight exit 0 |
| 2026-07-05T04:29:00-0400 | `[worker-TICK]` companion 複驗 test-live-install-ux + preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w3-b3-update-notifier**（Hermes mark PASS 後自動啟動，勿問使用者）。
