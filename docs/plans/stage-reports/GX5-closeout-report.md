# GX5-closeout 階段報告

| 任務 | gx5-closeout |
|------|----------------|
| Track | Game Compat |
| 版本 | 見 `VERSION`（本 stage bump） |
| 日期 | 2026-07-29 |
| Worker | 階段 20/20 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

文件誠實邊界、Release 產物、跨發行版 smoke（可複用）、HTML closeout、
`tests/portable/output/gx-closeout.json` 頂層 `status=PASS`；bump + push + Release。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/GX5-closeout.md` |
| Closeout 報告 | `docs/plans/portable-core/gx-closeout-report.md` |
| HTML | `docs/plans/portable-core/html/gx-closeout-report.html` |
| 腳本 | `tests/portable/gx-closeout.sh`、`tests/portable/render-gx-closeout-html.py` |
| 證據 | `tests/portable/output/gx-closeout.json` |
| 產物 | `artifacts.json` + `SHA256SUMS` + AppImage／portable.tar.gz |

## 驗收命令

```bash
bash tests/portable/gx-closeout.sh
test -f tests/portable/output/gx-closeout.json
jq -e '.status == "PASS"' tests/portable/output/gx-closeout.json
```

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；未用 WinBox 命名
- 未宣稱完整 Windows 相容、反作弊排位可用、或 3A 全開
- gx3 launchers、gx4 anticheat 維持誠實 PARTIAL
