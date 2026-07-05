# W4-D3 Hub 設定中心階段報告

| 任務 | w4-d3-hub-settings |
|------|---------------------|
| 版本 | 0.4.1.17 |
| 日期 | 2026-07-05 |
| Worker | 階段 17/47（w4-d3-hub-settings） |
| 結果 | **Hermes mark PASS**（2026-07-05T06:09:33-0400） |

## 目標

Hub 升格為 StrawWU 系統設定中心：Settings 類別 desktop、About/法律文件/bug 入口、Windows 相容分頁、GNOME 系統捷徑。

## 交付物

| 類型 | 路徑 |
|------|------|
| Hub 源碼 | `hub/`（`components/strawwu-hub` → symlink） |
| 設定 manifest | `hub/resources/settings-manifest.json` |
| settings 後端 | `hub/src/main/settings-service.js`、`hub/src/common/settings-paths.js` |
| UI 分頁 | `hub/src/renderer/index.html` — about / wincompat / system |
| 第三方聲明 | `os-image/config/branding/usr/share/strawwu/legal/third-party.html` |
| desktop 升格 | `hub/resources/strawwu-hub.desktop` — `Categories=Settings;System` |
| 單元測試 | `hub/test/settings.test.js`（47 tests total） |
| Preflight | `tests/preflight/test-hub-settings.sh` |
| baseline | `docs/plans/baselines/hub-settings-baseline.json` |
| Makefile | `test-hub`、`test-hub-settings`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 設定中心定位 | desktop `Name=StrawWU Settings`、`Categories=Settings;System` |
| About 分頁 | 版本/os-release、privacy/eula/third-party 開啟、bug reporter 啟動 |
| Windows 相容 | `strawwu status` + compat-matrix 等級卡片（EAC/BE/Vanguard） |
| 系統捷徑 | Wi-Fi/Network/Display/Sound/Power/Region/Users → GNOME panel `.desktop` |
| 既有面板保留 | status、logs、updates、language |
| 法律文件 | dev 路徑 branding overlay；installed `/usr/share/strawwu/legal/` |
| i18n | en/zh 完整新 key；206 語言 stub fallback |

## 驗收命令輸出（2026-07-05T06:07–06:08 UTC-4，companion re-verify）

### `make -C components test-hub` — exit 0（~0.4s）

Log: `/tmp/w4-d3-test-hub.log`

```
ℹ tests 47
ℹ suites 5
ℹ pass 47
ℹ fail 0
=== test-hub: PASS ===
```

### `make test-hub-settings` — exit 0（~0.6s）

Log: `/tmp/w4-d3-test-hub-settings.log`

```
PASS: desktop Categories=Settings;System
PASS: desktop Name=StrawWU Settings
PASS: renderer panel tab-about / tab-wincompat / tab-system
PASS: settings manifest schema valid
PASS: hub npm test (47/47)
PASS: baseline written hub-settings-baseline.json
=== W4-D3 hub-settings done: PASS ===
```

關鍵檢查：settings manifest、Settings desktop、about/wincompat/system 面板、legal 三文件、hub npm test 47 PASS、`hub-settings-baseline.json` 寫入。

### `make preflight` — exit 0（~40s）

Log: `/tmp/w4-d3-preflight.log`

含 W0 baseline + W1–W3 全部階段 + W4-D2 strawwu-shell + **W4-D3 hub-settings** exit 0（最終行 `=== W4-D3 hub-settings done: PASS ===`，整體 EXIT: 0）。

## 技術備註（治本）

1. **升格而非新建**：在既有 Electron Hub 上擴充分頁與 IPC，不複製 legacy；manifest JSON 定義 panels/legal/shortcuts 契約。
2. **dev/installed 雙路徑**：`settings-paths.js` 優先 `/usr/share/strawwu/`，開發時 fallback 至 branding overlay 與 compat-matrix dev 輸出。
3. **Windows compat 合流**：對齊 `strawwu-windows-compat-integration-plan.md` D3 合流點（session + grade）；Vanguard grade=F 為設計邊界。
4. **法律入口**：W2-trust LEG2 交付的 privacy/eula + 本階段 third-party；firstboot 連結仍留 W5-N3。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| compat-matrix 進 rootfs | 需 packaging/chroot 安裝至 `/usr/share/strawwu/` |
| Apps 分頁 | 待 **w4-r2-apps-page** |
| Flathub Hub 整合 | 待 **w4-f3-flathub-hub** |
| Registry launcher | 待 **w4-w1-registry-launcher** |
| 家庭帳號 Hub 分頁 | deferred-scope §1，v1.0+ |
| Playwright Hub UI E2E | 待 ISO/live 環境 |

## VERSION

`0.4.1.16` → `0.4.1.17`（iterate）

## 建議 commit message

```
feat(w4): elevate Hub to system settings center

- About/legal/bug-report, Windows compat grades, GNOME system shortcuts
- Settings desktop category, settings-manifest.json, settings-service IPC
- test-hub-settings preflight + hub-settings-baseline.json + Makefile
Tests: make -C components test-hub PASS, make test-hub-settings PASS, make preflight PASS
Version: 0.4.1.17
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T05:52:19-0400 | `[worker-START]` companion supervisor |
| 2026-07-05T05:57:00-0400 | `[worker-VERIFY]` 接手驗收 w4-d3-hub-settings |
| 2026-07-05T06:00:00-0400 | `[worker-DONE]` test-hub + test-hub-settings + preflight exit 0 — 待 Hermes mark PASS |
| 2026-07-05T06:07:20-0400 | `[worker-TICK]` companion periodic check status=IN_PROGRESS |
| 2026-07-05T06:08:00-0400 | `[worker-VERIFY]` companion re-run test-hub + test-hub-settings + preflight exit 0 — 待 Hermes mark PASS |
| 2026-07-05T06:09:33-0400 | `[worker-PASS]` Hermes mark PASS → next=w4-r2-apps-page |
| 2026-07-05T06:10:00-0400 | `[worker-VERIFY]` 本 worker 重跑 test-hub + test-hub-settings + preflight exit 0（確認 PASS 狀態） |

## 重驗輸出（2026-07-05T06:10 UTC-4）

| 命令 | 結果 | Log |
|------|------|-----|
| `make -C components test-hub` | exit 0，47/47 pass | `/tmp/w4-d3-test-hub-rerun.log` |
| `make test-hub-settings` | exit 0 | `/tmp/w4-d3-test-hub-settings-rerun.log` |
| `make preflight` | exit 0（~105s） | `/tmp/w4-d3-preflight-rerun.log` |

## 下一步

**w4-r2-apps-page**（已由 Hermes 啟動下一階段）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make -C components test-hub
make test-hub-settings
make preflight
```
