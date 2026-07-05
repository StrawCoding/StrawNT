# W4-R2 Hub Apps 分頁階段報告

| 任務 | w4-r2-apps-page |
|------|-----------------|
| 版本 | 0.4.1.18 |
| 日期 | 2026-07-05 |
| Worker | 階段 18/47（w4-r2-apps-page） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Hub「應用程式」分頁 — 顯示 `strawwu-app-registry` 登錄表、搜尋/篩選、受保護 app 邊界、透過 CLI 移除（dry-run + commit）。

## 交付物

| 類型 | 路徑 |
|------|------|
| 後端服務 | `hub/src/main/app-registry-service.js` |
| 路徑解析 | `hub/src/common/settings-paths.js` — `resolveAppRegistry` / `resolveAppRegistryCli` |
| IPC | `GET_APPS` · `PREVIEW_REMOVE_APP` · `REMOVE_APP`（main/preload/constants） |
| UI 分頁 | `hub/src/renderer/index.html` — `tab-apps`、搜尋、kind 篩選、app 卡片、移除 |
| 樣式 | `hub/src/renderer/styles.css` — apps panel |
| manifest | `hub/resources/settings-manifest.json` — `apps` panel + `app_registry` 契約 |
| i18n | `hub/locales/en.json`、`zh.json` — `nav.apps` / `apps.*` |
| 單元測試 | `hub/test/apps.test.js`（hub npm test 56 tests total） |
| Preflight | `tests/preflight/test-apps-page.sh` |
| baseline | `docs/plans/baselines/apps-page-baseline.json` |
| Makefile | `test-apps-page`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 登錄表來源 | installed `/var/lib/strawwu/app-registry.json`；dev fallback fixture |
| 列表 | 過濾 `install_state !== removed`；顯示 kind/source/backend/path |
| 搜尋/篩選 | 名稱/id/path 搜尋；win32/linux/flatpak/native 篩選 |
| 移除 | `strawwu-app-registry remove --dry-run` → `remove`；protected 拒絕 |
| dev/installed 雙路徑 | 對齊 W4-D3 settings-paths 模式 |
| 三表分離 | 僅讀 User App Registry；不混 compat-db / AppDatabase |

## 驗收命令輸出（2026-07-05T06:15:34-0400，worker 終驗）

### `make test-apps-page` — exit 0（~0.6s）

Log: `/tmp/w4-r2-test-apps-page.log`

```
=== W4-R2 apps-page preflight ===
PASS: plan strawwu-app-registry-plan.md
PASS: app-registry-service
PASS: settings manifest includes apps panel
PASS: renderer includes tab-apps / apps-list / btn-refresh-apps
PASS: IPC GET_APPS defined
PASS: cargo build strawwu-app-registry
ℹ tests 56 — pass 56 — fail 0
=== W4-R2 apps-page done: PASS ===
EXIT: 0
```

### `make preflight` — exit 0（~105s）

Log: `/tmp/w4-r2-preflight.log`

含 W0 baseline + W1–W3 全部階段 + W4-D2 strawwu-shell + W4-D3 hub-settings + **W4-R2 apps-page** 全部 exit 0（最終行 `=== W4-R2 apps-page done: PASS ===`，整體 `EXIT: 0`）。

## 技術備註（治本）

1. **CLI 為移除唯一寫入路徑**：Hub 讀檔列表、移除委派 `strawwu-app-registry`，保留 protected 檢查、日誌、W6-R5 deep-uninstall 語意。
2. **不複製 legacy**：在 W4-D3 Hub 上擴充 panel + IPC；manifest `app_registry` 定義契約。
3. **Phase 6 預設**：UI 顯示 `execution_backend`（預設 native）；container/microvm 僅覆寫展示。
4. **Flathub 邊界**：本階段僅已安裝 app 列表；Flathub browse/install 留 **w4-f3-flathub-hub**。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| Flathub Hub 整合 | 待 **w4-f3-flathub-hub** |
| Registry launcher | 待 **w4-w1-registry-launcher** |
| 桌面右鍵「從 StrawWU 移除」 | 待 **w5-d4-context-menu** |
| install hooks / deep uninstall | 待 **w5-r4** / **w6-r5** |
| Playwright Hub UI E2E | 待 ISO/live 環境 |
| polkit 授權 UI | CLI 層 protected；Hub 顯示 disabled 按鈕 |

## VERSION

`0.4.1.17` → `0.4.1.18`（iterate）

## 建議 commit message

```
feat(w4): add Hub Apps page for app registry UI

- Apps panel with search/filter, list cards, remove via strawwu-app-registry CLI
- app-registry-service IPC, settings-manifest app_registry contract, en/zh i18n
- test-apps-page preflight + apps-page-baseline.json + Makefile
Tests: make test-apps-page PASS, make preflight PASS
Version: 0.4.1.18
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T06:09:33-0400 | `[worker-START]` companion supervisor started |
| 2026-07-05T06:15:34-0400 | `[worker-DONE]` test-apps-page + preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w4-f3-flathub-hub**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-apps-page
make preflight
```
