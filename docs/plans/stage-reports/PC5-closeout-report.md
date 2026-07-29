# PC5-closeout 階段報告

| 任務 | pc5-closeout |
|------|----------------|
| Track | Portable Core A+3 |
| 版本 | 見 `VERSION`（本 stage bump） |
| 日期 | 2026-07-29 |
| Worker | 階段 6/6 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

使用者文件、產物索引、SHA256、version bump、將 `portable-core-a3` 合併並 push `main`、
產出 `tests/portable/output/closeout.json`（含 HTML 交付）。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/PC5-closeout.md` |
| 使用者指南 | `docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md` |
| 產物索引 | `docs/plans/portable-core/artifacts.json` |
| SHA256 | `tests/portable/output/SHA256SUMS` |
| Closeout 報告 | `docs/plans/portable-core/closeout-report.md` |
| HTML | `docs/plans/portable-core/html/portable-closeout-report.html` |
| 腳本 | `tests/portable/closeout.sh`、`tests/portable/render-closeout-html.py` |
| 證據 | `tests/portable/output/closeout.json` |

## 驗收命令

```bash
bash tests/portable/closeout.sh
jq -e '.status == "PASS"' tests/portable/output/closeout.json
```

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未動主工作區 ISO／T1 未提交改動
- Flatpak 維持誠實 PARTIAL
- 未宣稱完整 Windows 相容；未用 Wine／Proton／WinBox
