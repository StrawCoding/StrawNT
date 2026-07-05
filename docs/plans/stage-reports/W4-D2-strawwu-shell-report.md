# W4-D2 StrawWU Shell 階段報告

| 任務 | w4-d2-strawwu-shell |
|------|---------------------|
| 版本 | 0.4.1.16 |
| 日期 | 2026-07-05 |
| Worker | 階段 16/47（w4-d2-strawwu-shell） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

GNOME Shell fork profile + 內建 Dock；移除 Ubuntu 擴充依賴，session 改用 `strawwu` 模式。

## 交付物

| 類型 | 路徑 |
|------|------|
| shell deb | `os-image/debs/strawwu-shell/` |
| launcher | `os-image/debs/strawwu-shell/usr/bin/strawwu-shell` |
| session mode | `os-image/debs/strawwu-shell/usr/share/gnome-shell/modes/strawwu.json` |
| 內建 Dock 擴充 | `os-image/debs/strawwu-shell/usr/share/gnome-shell/extensions/strawwu-dock@strawwu/` |
| shell 設定 | `os-image/debs/strawwu-shell/usr/share/strawwu/shell/` |
| gschema | `os-image/debs/strawwu-shell/usr/share/glib-2.0/schemas/10_strawwu-shell.gschema.override` |
| 單元測試 | `os-image/debs/strawwu-shell/tests/test-shell.py` |
| Preflight | `tests/preflight/test-strawwu-shell.sh` |
| baseline | `docs/plans/baselines/shell-baseline.json` |
| Makefile | `test-strawwu-shell`；`preflight` 含本階段 |
| session 整合 | `strawwu-session` / `strawwu-desktop` / `target-manifest.yaml` 更新 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| Fork 策略 | **session-mode-overlay**：包裝 upstream `gnome-shell`，不複製 legacy 源碼 |
| Session mode | `GNOME_SHELL_SESSION_MODE=strawwu` + `strawwu.json`（StrawWU-Dark 主題、僅啟用內建 dock） |
| 內建 Dock | `strawwu-dock@strawwu` GJS 擴充（底部 dock chrome；非公開 extension API） |
| Ubuntu 擴充封鎖 | gschema `disabled-extensions` + manifest；不啟用 ubuntu-dock/ding/appindicators |
| strawwu-session | 改為 strawwu 模式；Depends `strawwu-shell` |
| strawwu-desktop | Depends `strawwu-shell`（取代直接 gnome-shell 依賴） |
| target 安裝順序 | manifest：`strawwu-shell` → `strawwu-session` |
| 插件 API | **延後**（deferred-scope §5；v1.0 extension point） |

## 驗收命令輸出（2026-07-05T05:40 UTC-4）

### `make test-strawwu-shell` — exit 0（~0.5s）

Log: `/tmp/w4-d2-test-strawwu-shell.log`

```
=== W4-D2 strawwu-shell done: PASS ===
```

關鍵檢查項：8 單元測試 PASS、`strawwu-shell_0.4.1.16_all.deb`（2.9K）、session mode 僅啟用 strawwu-dock、Ubuntu 擴充未列入 enabled、session/desktop/manifest 整合、`shell-baseline.json` 寫入。

### `make preflight` — exit 0（~105s）

Log: `/tmp/w4-d2-preflight.log`

含 W0 baseline + W1–W3 全部階段 + **W4-D2 strawwu-shell** exit 0。desktop-stack 複驗 PASS（session 已切換 strawwu 模式）。

## 技術備註（治本）

1. **乾淨室 fork**：不 patch gnome-shell 二進位；以 session mode + 內建擴充 + gschema 達成 StrawWU 桌面差異化，對齊 Pantheon/Cinnamon「自研 shell profile」路線。
2. **內建 vs 插件 API**：`strawwu-dock@strawwu` 隨 deb 系統安裝、由 mode 強制啟用；不提供第三方載入/市集（v0.5 deferred）。
3. **Ubuntu 擴充移除**：mode 的 `enabledExtensions` 不含 ubuntu-dock；gschema 額外 blocklist 防止 user 模式回退。
4. **過渡 rootfs**：squashfs 尚未 chroot 安裝 strawwu-shell（需 `chroot-install-target-setup` 重跑）；deb scaffold + preflight 已就緒。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| chroot / ISO 安裝 strawwu-shell | 需重跑 target-setup chroot（manifest 已更新） |
| Dock 圖示/App 整合 | 內建 dock 目前為 layout stub；完整 app well 整合待後續迭代 |
| gnome-shell 二進位 divert | 未做；launcher 包裝 upstream binary |
| Hub 設定中心 | 待 **w4-d3-hub-settings** |
| GDM greeter 品牌 | 待 W5-grt-session |
| 插件 extension point | 待 v1.0 |

## VERSION

`0.4.1.15` → `0.4.1.16`（iterate）

## 建議 commit message

```
feat(w4): add strawwu-shell fork profile with built-in dock

- strawwu session mode, strawwu-dock@strawwu built-in extension
- Block ubuntu-dock/ding/appindicators; session/desktop depend on strawwu-shell
- test-strawwu-shell preflight + shell-baseline.json + Makefile
Tests: make test-strawwu-shell PASS, make preflight PASS
Version: 0.4.1.16
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T05:36:09-0400 | `[worker-START]` companion supervisor started |
| 2026-07-05T05:40:00-0400 | `[worker-DONE]` test-strawwu-shell + preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w4-d3-hub-settings**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-strawwu-shell
make preflight
```
