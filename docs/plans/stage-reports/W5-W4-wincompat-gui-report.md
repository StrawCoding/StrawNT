# W5-W4 Windows GUI Smoke 階段報告

| 任務 | w5-w4-wincompat-gui |
|------|---------------------|
| 版本 | 0.4.1.31 |
| 日期 | 2026-07-05 |
| Worker | 階段 28/47（w5-w4-wincompat-gui） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

GUI app 啟動 smoke — PE GUI 子系統（notepad 等）經 `strawwu run` 建立 Win32 視窗、Wayland present bridge（Mutter 合約），並寫入 desktop entry + wincompat.log。

## 交付物

| 類型 | 路徑 |
|------|------|
| GUI smoke 模組 | `components/strawwu-runtime/src/gui_smoke.rs` |
| Launcher desktop 注入 | `components/strawwu-launcher/src/desktop.rs` |
| wincompat.log 寫入 | `components/strawwu-launcher/src/log.rs` |
| PE stub 載入 | `components/strawwu-launcher/src/pe_loader.rs` |
| `strawwu run` 整合 | `components/strawwu-launcher/src/main.rs` — execute_pe + gui_smoke + registry desktop_entry |
| Registry upsert | `upsert_from_launch(..., desktop_entry)` |
| baseline 元資料 | `os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml`（gui_smoke 區段） |
| Preflight | `tests/preflight/test-wincompat-gui.sh` |
| baseline JSON | `docs/plans/baselines/wincompat-gui-baseline.json` |
| Makefile | `test-wincompat-gui`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| GUI PE 偵測 | `PeSubsystem::WindowsGui` → 觸發 smoke |
| Win32 視窗 | `WindowManager` RegisterClass → CreateWindow → ShowWindow |
| 合成器橋接 | `PresentBridge`（Wayland 預設，compositor=mutter） |
| PE 執行 | `execute_pe` 完整 runtime 流程（非僅 launch_app stub） |
| 缺檔 smoke | 路徑 `.exe` 但檔案不存在時以 stub GUI PE 驗證 |
| Desktop entry | `~/.local/share/applications/{app_id}.desktop`（`STRAWWU_DESKTOP_DIR` 可覆寫） |
| Registry | `run` upsert 含 `desktop_entry`（W5-D4 待辦：launcher 自動注入） |
| 結構化日誌 | `STRAWWU_WINCOMPAT_LOG` / `/var/log/strawwu/wincompat.log` — `gui_smoke` 事件 |

## 驗收命令輸出（2026-07-05 UTC-4）

### `make test-wincompat-gui` — exit 0（~0.5s）

Log: `/tmp/w5-w4-test-wincompat-gui-cursor.log`

```
=== W5-W4 wincompat-gui done: PASS ===
```

關鍵檢查（17 項全 PASS）：

- `cargo build strawwu-launcher`、`cargo test gui_smoke`（4 tests）、`cargo test launcher desktop`
- `strawwu run notepad.exe` → `gui-smoke=PASS`、`compositor=mutter`
- `notepad.desktop` 含 `X-StrawWU-App-Id=notepad`
- registry `desktop_entry` 含 `notepad.desktop`
- `wincompat.log` 含 `gui_smoke` 事件

範例 CLI 輸出：

```
strawwu: launched /tmp/.../notepad.exe (format=PE, pid=1, backend=native, app_id=notepad, gui-smoke=PASS hwnd=65536 compositor=mutter visible=true)
```

### `make preflight` — exit 0（~115s）

Log: `/tmp/w5-w4-preflight-cursor.log`

含 W0–W5 全部階段 + **W5-W4 wincompat-gui**（行 1208：`=== W5-W4 wincompat-gui done: PASS ===`）；最終階段 W5-B4 disable-upstream-init 亦 PASS。

WARN（預期/環境）：W5-B4 `ubuntu-desktop` 仍留 rootfs/squashfs（disable-upstream-init 標 WARN，不阻斷 PASS）。

### chroot 同步

Log: `/tmp/w5-w4-chroot-target-setup.log`、`chroot-install-wincompat`（0.4.1.31 deb，baseline.yaml gui_smoke 區段）

## 技術備註（治本）

1. **Phase 6 誠實 smoke**：未宣稱真實 Windows 二進位在 Mutter 上繪製；驗證 Win32 HWND 生命週期 + present bridge 合約，對齊 integration plan W4 DoD。
2. **run 路徑收斂**：W4-W1 registry 整合 + W5-W4 execute_pe/gui_smoke/desktop 一次完成，避免 launcher 與 runtime 分叉。
3. **Desktop Action 邊界**：本階段寫入 `.desktop` + registry `desktop_entry`；`RemoveFromStrawWU` Desktop Action 注入仍可由 W5-D4 `inject-action` 後續補強（非本階段阻斷項）。
4. **環境變數**：`STRAWWU_DESKTOP_DIR`、`STRAWWU_WINCOMPAT_LOG`、`STRAWWU_DISPLAY_BACKEND`（wayland|x11）供 preflight/E2E 隔離。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 真實 notepad.exe 像素/輸入 | 待 W6-W6 E2E / 實機 |
| Mutter 原生 surface 綁定 | present bridge 仍為 simulation PoC |
| Desktop Action 自動 inject | W5-D4 工具已就緒；launcher 可選呼叫 |
| Hub wincompat 分頁即時 session | 待 w5-grt-session |
| Playwright 桌面 icon 啟動 | 待 ISO/live |

## 變更檔案清單

```
VERSION (0.4.1.30 → 0.4.1.31)
Makefile
components/strawwu-runtime/Cargo.toml
components/strawwu-runtime/src/{lib,gui_smoke}.rs
components/strawwu-launcher/Cargo.toml
components/strawwu-launcher/src/{main,lib,registry,desktop,log,pe_loader}.rs
components/strawwu-app-registry/src/registry.rs
os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml
tests/preflight/test-wincompat-gui.sh                           (新增)
docs/plans/baselines/wincompat-gui-baseline.json                  (新增)
docs/plans/stage-reports/W5-W4-wincompat-gui-report.md            (本檔)
```

## VERSION

`0.4.1.30` → `0.4.1.31`（iterate）

## 建議 commit message

```
feat(w5): Windows GUI app launch smoke via strawwu run

- gui_smoke: Win32 HWND + Wayland present bridge (mutter contract)
- strawwu run: execute_pe, desktop entry, wincompat.log, registry desktop_entry
Tests: make test-wincompat-gui PASS, make preflight PASS
Version: 0.4.1.31
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T10:05 UTC-4 | `[worker-START]` w5-w4-wincompat-gui |
| 2026-07-05T10:16 UTC-4 | 前次 worker：test-wincompat-gui + preflight exit 0 |
| 2026-07-05T10:26 UTC-4 | Cursor worker 複驗：`make test-wincompat-gui` exit 0、`make preflight` exit 0 — 待 Hermes mark |

## 下一階段

**w5-grt-session**（Hermes mark PASS 後自動啟動，勿問使用者）。
