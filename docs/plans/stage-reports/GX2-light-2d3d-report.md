# GX2 — Light 2D/3D Games 階段報告

| 任務 | gx2-light-2d3d |
|------|----------------|
| Track | Game Compat |
| 版本 | 0.7.1.29 |
| 日期 | 2026-07-29 |
| Worker | 階段 17/20 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

在 Portable **native** 路徑完成至少 2 個公開輕量 2D/3D Win 遊戲標竿之啟動證據，並輸出 `PASS/PARTIAL` 驗收 JSON。

## 交付物

| 類型 | 路徑 |
|------|------|
| 標竿清單 | `tests/portable/gx-light-games-manifest.json` |
| 煙測腳本 | `tests/portable/smoke-gx-light-games.sh` |
| 原始探針證據 | `tests/portable/output/gx2-light-games-raw.json` |
| 驗收證據 | `tests/portable/output/gx-light-games.json` |

## 本階段標竿

- `supertuxkart-demo`：公開輕量 3D 小遊戲級（launcher_only）
- `openra-demo`：公開輕量 2D RTS 小遊戲級（launcher_only）

## 本地驗證結果

- 執行：`bash tests/portable/smoke-gx-light-games.sh`
- 測試：`cargo test -p strawwu-runtime golden_apps -- --nocapture`（6 passed）
- 證據：`tests/portable/output/gx-light-games.json` 目前為 `status=PASS`（version=0.7.1.29），`verified=2/2`

## Hermes 驗收命令（由 Hermes runner 執行）

```bash
test -f tests/portable/output/gx-light-games.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/gx-light-games.json
jq -e '(.apps|length) >= 2 or (.results|length) >= 2' tests/portable/output/gx-light-games.json
```

## 誠實邊界（known_limitations）

- 僅 `launcher_only` 啟動探針，不宣稱完整遊玩覆蓋
- 不宣稱反作弊／排位可用
- 不宣稱 3A 完整相容

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows 相容
