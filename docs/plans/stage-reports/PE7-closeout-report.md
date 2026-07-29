# PE7-closeout 階段報告

| 任務 | pe7-closeout |
|------|----------------|
| Track | Native PE Real Exec |
| 版本 | 見 `VERSION`（本 stage bump） |
| 日期 | 2026-07-29 |
| Worker | 階段 14/14 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

文件更正、Release 產物、跨發行版 smoke、HTML closeout、
`tests/portable/output/pe-closeout.json` 頂層 `status=PASS`；bump + push + Release。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/PE7-closeout.md` |
| Closeout 報告 | `docs/plans/portable-core/pe-closeout-report.md` |
| HTML | `docs/plans/portable-core/html/pe-closeout-report.html` |
| 腳本 | `tests/portable/pe-closeout.sh`、`tests/portable/render-pe-closeout-html.py` |
| 證據 | `tests/portable/output/pe-closeout.json` |
| 產物 | `artifacts.json` + `SHA256SUMS` + AppImage／portable.tar.gz |

## 驗收命令

```bash
bash tests/portable/pe-closeout.sh
test -f tests/portable/output/pe-closeout.json
jq -e '.status == "PASS"' tests/portable/output/pe-closeout.json
```

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；未用 WinBox 命名
- 未宣稱完整 Windows／反作弊通過
- pe6 golden 維持誠實 PARTIAL
