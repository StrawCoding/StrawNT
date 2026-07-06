# W8-DOC handbook 階段報告

| 任務 | w8-doc-handbook |
|------|-----------------|
| 版本 | 0.5.0.8 |
| 日期 | 2026-07-06 |
| Worker | 階段 46/47（w8-doc-handbook） |
| 最後驗證 | 2026-07-06T08:04 UTC-4（階段 46 worker 重驗） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

交付 StrawWU **使用者＋管理員完整手冊**（`docs/user/handbook/`），整合 DOC2（Windows 相容分級）與 DOC3（升級／rollback 誠實邊界），含 HTML hermes-deliver 產物與 preflight gate。

## 交付物

| 類型 | 路徑 |
|------|------|
| 手冊索引 | `docs/user/handbook/README.md` |
| 使用者手冊 | `docs/user/handbook/user-handbook.md` |
| 管理員手冊 | `docs/user/handbook/admin-handbook.md` |
| Windows 相容（DOC2） | `docs/user/handbook/wincompat-guide.md` |
| 升級救援（DOC3） | `docs/user/handbook/upgrade-rescue-guide.md` |
| 機器可讀清單 | `docs/user/handbook/manifest.json` |
| HTML（hermes-deliver） | `docs/user/handbook/html/*.html`（4 冊） |
| HTML 渲染器 | `tests/handbook/render-html.py` |
| 驗證腳本 | `tests/handbook/validate-handbook.py` |
| Preflight gate | `tests/preflight/test-handbook.sh` |
| baseline JSON | `docs/plans/baselines/handbook-baseline.json` |
| Makefile | `test-handbook`；`preflight` 串接 |
| 上層索引更新 | `docs/user/README.md`、`docs/user/manifest.json` |
| 計畫更新 | `docs/plans/strawwu-user-docs-plan.md` |
| VERSION | `0.5.0.8` |

## 功能摘要

| 冊別 | 說明 |
|------|------|
| **user-handbook** | strawwu-shell、Hub（設定／Apps／Flathub／wincompat）、應用安裝移除、fcitx5、更新、bug-reporter |
| **admin-handbook** | initd、target-setup、meta allowlist、APT 倉庫／keyring、release-iso 發佈、initramfs-hooks、hw-matrix |
| **wincompat-guide** | compat 等級 A/B/C/F、`strawwu status`、native 預設後端、反作弊誠實邊界、Q8 黃金啟動器 |
| **upgrade-rescue-guide** | v0.5 已實作 vs UPG 延後、`strawwu-upgrade --rollback` 未實作標示、升級失敗流程圖 |

### 誠實邊界

- 社群／支援 URL 維持 **TBD**（deferred scope §4）
- `strawwu-upgrade --rollback`、專用 Rescue GRUB 標為 UPG 路線圖
- WinBox／strawwu-box 明確禁止（Phase 6 cleanroom）

## 驗收命令輸出

### `make test-handbook` — exit 0

Log: `/tmp/w8-doc-test-handbook.log`

```
PASS: rendered docs/user/handbook/html/user-handbook.html
PASS: rendered docs/user/handbook/html/admin-handbook.html
PASS: rendered docs/user/handbook/html/wincompat-guide.html
PASS: rendered docs/user/handbook/html/upgrade-rescue-guide.html
=== W8-DOC handbook validation ===
（全 58 項 PASS，含 manifest schema v1、4 volumes、HTML Teal #14b8a6、VERSION 0.5.0.8）
=== W8-DOC handbook done: PASS ===
```

### `make preflight` — exit 0（~260s）

Log: `/tmp/w8-doc-preflight.log`

含 W0–W8-S4 全部階段 + **W8-DOC handbook** 終行：`=== W8-DOC handbook done: PASS ===`

### 重驗（2026-07-06 08:04 UTC-4，階段 46 worker）

| 命令 | 結果 | Log |
|------|------|-----|
| `make test-handbook` | exit 0 | `/tmp/w8-doc-test-handbook.log` |
| `make preflight` | exit 0（~260s） | `/tmp/w8-doc-preflight.log` |
| `make test-user-docs` | exit 0（回歸） | — |

### `make test-user-docs` — exit 0（回歸）

manifest 更新後 W6-DOC1 仍 PASS（VERSION 0.5.0.8）。

## 變更檔案清單

```
VERSION (0.5.0.7 → 0.5.0.8)
Makefile
docs/user/README.md
docs/user/manifest.json
docs/user/handbook/README.md                              (新增)
docs/user/handbook/manifest.json                          (新增)
docs/user/handbook/user-handbook.md                       (新增)
docs/user/handbook/admin-handbook.md                      (新增)
docs/user/handbook/wincompat-guide.md                     (新增)
docs/user/handbook/upgrade-rescue-guide.md                (新增)
docs/user/handbook/html/*.html                            (新增，render 產物)
tests/handbook/render-html.py                             (新增)
tests/handbook/validate-handbook.py                       (新增)
tests/preflight/test-handbook.sh                          (新增)
docs/plans/baselines/handbook-baseline.json               (新增)
docs/plans/strawwu-user-docs-plan.md                      (更新)
docs/plans/stage-reports/W8-DOC-handbook-report.md        (本檔)
```

## 設計決策

1. **手冊獨立子目錄**：`docs/user/handbook/` 與 DOC1 install/rescue 分層，避免單檔過長；上層 README 交叉連結。
2. **DOC2+DOC3 合併交付**：依 `strawwu-user-docs-plan.md` 與 w6-doc1 延後項，於 handbook 一次完成 wincompat 與 upgrade/rescue 誠實說明。
3. **渲染器複用**：handbook `render-html.py` 沿用 W6-DOC1 Teal 深色 hermes-deliver 樣式，標頭改為「StrawWU Handbook」。
4. **不擴產品 scope**：社群渠道 TBD、UPG rollback 標未實作；不宣稱 Windows／反作弊官方通過。

## 延後範圍（非阻塞）

| 項目 | 狀態 |
|------|------|
| 官方論壇 / Matrix / Discord | TBD（v1.0） |
| `strawwu-upgrade --rollback` 實作 | UPG4+ |
| 專用 Rescue GRUB 項目 | UPG5 |
| 多語系手冊（en 完整版） | 後續 l10n wave |

## 建議 commit message

```
feat(w8): add user+admin handbook with DOC2/DOC3 guides

- docs/user/handbook/ four volumes + HTML hermes-deliver
- validate-handbook.py + preflight gate + handbook-baseline.json
- Update docs/user index and user-docs-plan for DOC completion
Tests: make test-handbook PASS, make preflight PASS
Version: 0.5.0.8
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-handbook
make preflight
```

HTML 重新產生：`python3 tests/handbook/render-html.py`

## 下一階段

Hermes mark PASS → 自動啟動 **w8-mvp-closeout**（勿問使用者）。

## 時間線

| 時間 | 事件 |
|------|------|
| 2026-07-06 07:50 | `[worker-START]` 階段 46/47 w8-doc-handbook |
| 2026-07-06 07:52 | 交付 handbook 四冊 + 測試基礎設施 |
| 2026-07-06 07:53 | `make test-handbook` exit 0 |
| 2026-07-06 07:57 | `make preflight` exit 0 |
| 2026-07-06 07:57 | `[worker-DONE]` 待 Hermes mark PASS |
| 2026-07-06 08:00 | `[worker-TICK]` Hermes 階段 46 啟動，讀取 kickoff + 驗證現有交付 |
| 2026-07-06 08:04 | `make test-handbook` + `make preflight` + `make test-user-docs` 重驗 exit 0 |
| 2026-07-06 08:04 | `[worker-DONE]` 交付完整，待 Hermes mark PASS |
