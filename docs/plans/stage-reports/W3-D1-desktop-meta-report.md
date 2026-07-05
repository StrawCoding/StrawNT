# W3-D1 Desktop Meta 階段報告

| 任務 | w3-d1-desktop-meta |
|------|-------------------|
| 版本 | 0.4.1.10 |
| 日期 | 2026-07-05 |
| Worker | 階段 11/47（w3-d1-desktop-meta） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

strawwu-session + strawwu-desktop meta：GDM 可選 StrawWU session、宣告無 snap/遙測的 desktop meta 依賴集。

## 交付物

| 類型 | 路徑 |
|------|------|
| session deb | `os-image/debs/strawwu-session/` |
| desktop meta deb | `os-image/debs/strawwu-desktop/` |
| session launcher | `os-image/debs/strawwu-session/usr/bin/strawwu-session` |
| GDM xsessions | `os-image/debs/strawwu-session/usr/share/xsessions/strawwu-session.desktop` |
| GNOME session | `os-image/debs/strawwu-session/usr/share/gnome-session/sessions/strawwu.session` |
| Hub autostart | `os-image/debs/strawwu-session/etc/xdg/autostart/strawwu-hub-autostart.desktop` |
| session 單元測試 | `os-image/debs/strawwu-session/tests/test-session.py` |
| meta 單元測試 | `os-image/debs/strawwu-desktop/tests/test-meta.py` |
| Preflight | `tests/preflight/test-desktop-stack.sh`（W3-D1 強化） |
| baseline | `docs/plans/baselines/desktop-baseline.json` |
| Makefile | `test-desktop-stack`；`preflight` 含 desktop-stack |

## 功能摘要

| 項目 | 實作 |
|------|------|
| strawwu-session | GDM 註冊 `strawwu-session`；interim 以 GNOME Shell + `GNOME_SHELL_SESSION_MODE=ubuntu` 啟動 |
| strawwu.session | RequiredComponents 對齊 ubuntu.session；Name=StrawWU |
| Hub autostart | 僅在 `/opt/StrawWU Hub/strawwu-hub` 存在時啟動（`test -x` guard） |
| boot_selfcheck | 登入 session 時 best-effort 寫入 `strawwu-initd set lifecycle.boot_selfcheck done` |
| strawwu-desktop meta | Depends: strawwu-session + gdm3/gnome-shell/xorg + strawwu-initd/bug-reporter/flatpak-setup |
| 禁止依賴 | control 無 snapd/apport/whoopsie/ubuntu-report/ubuntu-pro-client |
| 過渡策略 | squashfs 仍保留 ubuntu-session/ubuntu-desktop；W5-B4 替換、W6-B5 審計 |

## 驗收命令輸出（2026-07-05T04:13 UTC-4，worker 複驗）

### `make test-desktop-stack` — exit 0（~0.6s）

Log: `/tmp/w3-d1-test-desktop-stack.log`

```
=== W3-D1 desktop-stack done: PASS ===
```

關鍵檢查項：session/meta deb scaffold、5+3 單元測試 PASS、`strawwu-session_0.4.1.10_all.deb`（2.1K）、`strawwu-desktop_0.4.1.10_amd64.deb`（1.5K）、GDM 註冊、forbidden deps absent、`desktop-baseline.json` 寫入、squashfs 已有 strawwu-* debs count=3（initd/flatpak/calamares 等，session/desktop 尚未 chroot 安裝）。

### `make preflight` — exit 0（~32s）

Log: `/tmp/w3-d1-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-N1 init-tools + W2-B2 bug-reporter + W2-I1 calamares-settings + W2-R1 app-registry + W2-trust SEC2/OBS1/LEG2 + **W3-D1 desktop-stack** 全部 exit 0。

## 技術備註（治本）

1. **過渡而非硬替換**：本階段交付 deb scaffold + preflight；ISO rootfs 仍用 ubuntu-desktop/ubuntu-session（W1-B1 保留）。W5-B4 才 disable upstream meta；W6-B5 做 ubuntu-* 清零審計。
2. **Interim compositor**：W4-D2 `strawwu-shell` 完成前，session 包裝 gnome-session；避免阻塞 Wave 3 其他桌面整合工作。
3. **Meta 無 telemetry**：strawwu-desktop 明確不 Recommends snapd/apport 等；與 W1-F2 apt pin 互補，為新安裝提供乾淨依賴宣告。
4. **strawwu-minimal 延後**：ubuntu-minimal → ubuntu-pro-client broken Depends 仍待 W5-B4/W6 處理；本階段未新增 strawwu-minimal deb（避免 scope 膨脹）。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| chroot / ISO 安裝 session+meta | 未打包進 rootfs；W3-N2 target-setup 或 W5 整合 |
| strawwu-shell 替換 GNOME | 待 W4-D2 |
| ubuntu-desktop 移除 | 待 W5-B4 |
| GDM greeter 品牌 | 待 W5-grt-session |
| strawwu-minimal（ubuntu-pro-client 替代） | 待 W5-B4 / W6-B5 |
| meta 審計 ubuntu-* 清零 | 待 W6-B5 |

## VERSION

`0.4.1.9` → `0.4.1.10`（iterate）

## 建議 commit message

```
feat(w3): add strawwu-session and strawwu-desktop meta deb scaffolds

- GDM strawwu-session with interim GNOME Shell launcher
- Meta package without snap/telemetry deps; depends on strawwu-* stack
- test-desktop-stack preflight + desktop-baseline.json + Makefile
Tests: make test-desktop-stack PASS, make preflight PASS
Version: 0.4.1.10
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T04:01:30-0400 | `[worker-DONE]` stage ended — 待 Hermes mark PASS |
| 2026-07-05T04:12:41-0400 | `[worker-TICK]` Hermes periodic check status=IN_PROGRESS |
| 2026-07-05T04:13:30-0400 | `[worker-DONE]` 複驗 test-desktop-stack + preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w3-i2-live-ux**（Hermes mark PASS 後自動啟動，勿問使用者）。
