# W4-F3 Hub Flathub 分頁階段報告

| 任務 | w4-f3-flathub-hub |
|------|-------------------|
| 版本 | 0.4.1.19 |
| 日期 | 2026-07-05 |
| Worker | 階段 19/47（w4-f3-flathub-hub） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Hub「Flathub」分頁 — browse/install MVP：瀏覽 Flathub 目錄、搜尋、透過 flatpak CLI 安裝；開發環境使用 fixture + 模擬安裝。

## 交付物

| 類型 | 路徑 |
|------|------|
| 後端服務 | `hub/src/main/flathub-service.js` |
| 路徑解析 | `hub/src/common/settings-paths.js` — `resolveFlatpakCli` / `resolveFlathubFixture` |
| IPC | `SEARCH_FLATHUB` · `GET_FLATHUB_STATUS` · `INSTALL_FLATHUB`（main/preload/constants） |
| UI 分頁 | `hub/src/renderer/index.html` — `tab-flathub`、搜尋、app 卡片、安裝按鈕 |
| 樣式 | `hub/src/renderer/styles.css` — flathub panel |
| manifest | `hub/resources/settings-manifest.json` — `flathub` panel + `flathub` 契約 |
| i18n | `hub/locales/en.json`、`zh.json` — `nav.flathub` / `flathub.*`（含第三方免責） |
| fixture | `hub/tests/fixtures/flathub-catalog.json` |
| 單元測試 | `hub/test/flathub.test.js`（hub npm test 66 tests total） |
| Preflight | `tests/preflight/test-flathub-hub.sh` |
| baseline | `docs/plans/baselines/flathub-hub-baseline.json` |
| Makefile | `test-flathub-hub`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 瀏覽 | 空搜尋 → Flathub API `/collection/popular`；有 flatpak 時走線上 API |
| 搜尋 | POST `/api/v2/search`；dev/無 flatpak → fixture 過濾 |
| 安裝 | `flatpak install -y --noninteractive --system flathub <appId>` |
| dev 模式 | 無 `/usr/bin/flatpak` 或 `STRAWWU_FLATHUB_FIXTURE=1` → fixture + 模擬安裝 |
| 已安裝狀態 | `flatpak list --app --system` 標記「已安裝」 |
| 法律合規 | UI 顯示 `flathub.disclaimer`（第三方維護，非 StrawWU 官方） |
| CSP | 允許 `dl.flathub.org` 圖示載入 |

## 驗收命令輸出（2026-07-05T06:40 UTC-4，companion 複驗）

### `make test-flathub-hub` — exit 0（~0.6s）

Log: `/tmp/w4-f3-test-flathub-hub.log`

```
=== W4-F3 flathub-hub preflight ===
PASS: plan strawwu-flathub-plan.md
PASS: flathub-service
PASS: settings manifest
PASS: flathub catalog fixture
PASS: settings manifest includes flathub panel
PASS: renderer includes tab-flathub / flathub-list / btn-refresh-flathub / flathub-disclaimer
PASS: sidebar nav flathub tab
PASS: IPC SEARCH_FLATHUB / INSTALL_FLATHUB defined
PASS: Makefile defines test-flathub-hub
PASS: preflight includes flathub-hub
ℹ tests 66 — suites 7 — pass 66 — fail 0 — duration_ms 178
PASS: hub npm test
PASS: baseline written docs/plans/baselines/flathub-hub-baseline.json
=== W4-F3 flathub-hub done: PASS ===
EXIT: 0
```

### `make preflight` — exit 0（~43s）

Log: `/tmp/w4-f3-preflight.log`

含 W0 baseline + W1–W3 全部階段 + W4-D2/D3/R2 + **W4-F3 flathub-hub** 全部 exit 0（最終行 `=== W4-F3 flathub-hub done: PASS ===`，整體 `EXIT: 0`）。

## 技術備註（治本）

1. **Hub 承接軟體管理**：對齊 PRD Mint/Pop 路線，Flathub browse/install 在 Hub 而非 gnome-software；Apps 分頁仍管已登錄 app registry。
2. **雙路徑 dev/installed**：有 flatpak CLI 走真實 API + install；開發/CI 用 fixture，API 失敗時 fallback fixture。
3. **不複製 legacy**：在 W4-R2 Hub 上擴充 panel + IPC；manifest `flathub` 定義 remote/api/fixture 契約。
4. **第三方免責**：對齊 `strawwu-legal-compliance-plan.md` §6。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| Registry launcher（安裝後登錄） | 待 **w4-w1-registry-launcher** |
| target Flathub E2E（安裝後 remote） | 待 **w6-f5-target-flathub** |
| Playwright Hub UI E2E | 待 ISO/live 環境 |
| polkit 授權 UI | install 委派 flatpak；失敗顯示 error 狀態 |
| 離線 Flathub 快取 | MVP 僅 API + fixture fallback |

## VERSION

`0.4.1.18` → `0.4.1.19`（iterate）

## 建議 commit message

```
feat(w4): add Hub Flathub browse/install MVP

- Flathub panel with search, catalog cards, flatpak install via IPC
- flathub-service with API + dev fixture, third-party disclaimer i18n
- test-flathub-hub preflight + flathub-hub-baseline.json + Makefile
Tests: make test-flathub-hub PASS, make preflight PASS
Version: 0.4.1.19
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T06:24 UTC-4 | `[worker-START]` w4-f3-flathub-hub |
| 2026-07-05T06:28 UTC-4 | `[worker-TICK]` 複驗實作完整性 — 程式碼已就緒 |
| 2026-07-05T06:30 UTC-4 | `[worker-DONE]` test-flathub-hub + preflight exit 0 — 待 Hermes mark PASS |
| 2026-07-05T06:39 UTC-4 | `[worker-TICK]` companion periodic check — IN_PROGRESS |
| 2026-07-05T06:40 UTC-4 | `[worker-DONE]` companion 複驗 test-flathub-hub + preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w4-w1-registry-launcher**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-flathub-hub
make preflight
```
