# W6-W6 Windows Compat E2E 階段報告

| 任務 | w6-w6-wincompat-e2e |
|------|---------------------|
| 版本 | 0.4.1.38 |
| 日期 | 2026-07-05 |
| Worker | 階段 35/47（w6-w6-wincompat-e2e） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Windows compat 完整 CLI E2E：**install → 桌面 icon → launch → remove**

對齊 `strawwu-windows-compat-integration-plan.md` W6 DoD。

## 交付物

| 類型 | 路徑 |
|------|------|
| E2E preflight | `tests/preflight/test-wincompat-e2e.sh` |
| E2E smoke 入口 | `tests/e2e/wincompat-smoke.sh` |
| baseline YAML 擴充 | `os-image/debs/strawwu-wincompat/.../baseline.yaml`（`e2e_flow`） |
| baseline JSON | `docs/plans/baselines/wincompat-e2e-baseline.json` |
| Makefile | `test-wincompat-e2e`；`preflight` 含本階段 |

## 功能摘要

| 步驟 | 驗證內容 |
|------|----------|
| **install** | `strawwu install setup.exe` → registry `pending` + `source=installer` |
| **icon** | `strawwu run notepad.exe` → `notepad.desktop` + `X-StrawWU-App-Id` + registry `installed` |
| **launch** | 解析 desktop `Exec=` 行並重跑 → `gui-smoke=PASS` + `wincompat.log` |
| **remove** | `strawwu-app-registry remove-by-desktop --deep` → 刪 desktop + registry 移除 |
| **整合** | `desktop-actions/core.py remove_desktop` 與 context menu 同路徑 |

## 驗收命令輸出（2026-07-05 22:25 UTC-4，worker 終驗）

### `make test-wincompat-e2e` — exit 0（~0.5s）

Log: `/tmp/w6-w6-test-wincompat-e2e.log`

```
=== W6-W6 wincompat-e2e done: PASS ===
```

關鍵檢查（22 項全 PASS）：install pending、run 建 icon、desktop Exec 重啟動、deep remove 清檔、desktop-actions 移除。

### `make preflight` — exit 0（~168s）

Log: `/tmp/w6-w6-preflight.log`

含 W0–W6-R5 全部階段 + **W6-W6 wincompat-e2e** 全部 exit 0（終行：`=== W6-W6 wincompat-e2e done: PASS ===`）。

## 變更檔案清單

```
VERSION (0.4.1.37 → 0.4.1.38)
Makefile
os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml
tests/preflight/test-wincompat-e2e.sh                           (新增)
tests/e2e/wincompat-smoke.sh                                    (新增)
docs/plans/baselines/wincompat-e2e-baseline.json                (新增)
docs/plans/stage-reports/W6-W6-wincompat-e2e-report.md          (本檔)
```

## 技術備註（治本）

1. **四步 E2E 串接**：沿用既有 W4-W1 registry、W5-W4 GUI smoke、W6-R5 deep remove，不新增平行移除路徑；`remove-by-desktop --deep` 與 Hub/桌面右鍵一致。
2. **Desktop Exec 啟動**：測試將 `components/target/debug` 加入 `PATH`，模擬 Live 上 `/usr/bin/strawwu` 在 PATH 的桌面啟動行為。
3. **誠實邊界**：本階段為 CLI harness E2E；ISO/live Playwright 與 Mutter 像素驗證留待 Hermes release-iso 閘門，不宣稱完整 Windows 相容。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| Live ISO Playwright 點擊桌面 icon | 待 Hermes release-iso / w6-hw1 |
| 真實 PE 二進位像素/輸入 | Phase 6 誠實 smoke |
| `strawwu install` 完整 installer 解包 | 仍為 stub；run 路徑為主驗證 |
| chroot 重打包 | baseline.yaml `e2e_flow` 需 dev-iso 同步 |

## VERSION

`0.4.1.37` → `0.4.1.38`（iterate）

## 建議 commit message

```
feat(w6): Windows compat install→icon→launch→remove E2E harness

- test-wincompat-e2e preflight chains install, desktop icon, Exec launch, deep remove
- wincompat-smoke.sh + baseline e2e_flow metadata
Tests: make test-wincompat-e2e PASS, make preflight PASS
Version: 0.4.1.38
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T22:15 UTC-4 | `[worker-START]` 階段 35/47 w6-w6-wincompat-e2e |
| 2026-07-05T22:25 UTC-4 | `[worker-DONE]` 終驗：`make test-wincompat-e2e` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w6-hw1-live-usb**（Hermes mark PASS 後自動啟動，勿問使用者）。
