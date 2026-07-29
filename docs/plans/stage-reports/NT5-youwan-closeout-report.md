# NT5 — Youwan Closeout 階段報告

| 任務 | nt5-youwan-closeout |
|------|----------------------|
| Track | StrawNT 優玩 |
| 產品 | StrawNT |
| 版本 | 0.7.1.38 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

完成 StrawNT 優玩 closeout：使用者文件、誠實邊界、Release 產物、SHA256、必要跨發行版 smoke、HTML closeout；產出 `tests/strawnt/output/nt5-closeout.json` 頂層 PASS；bump+push+GitHub Release。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/NT5-youwan-closeout.md` |
| Closeout 報告 | `docs/plans/portable-core/nt5-closeout-report.md` |
| HTML | `docs/plans/portable-core/html/nt5-closeout-report.html` |
| 煙測腳本 | `tests/strawnt/nt5-youwan-closeout.sh` |
| 驗收證據 | `tests/strawnt/output/nt5-closeout.json` |
| 產物／SHA256 | `docs/plans/portable-core/artifacts.json`、`tests/portable/output/SHA256SUMS` |

## 前序階段

| Stage | 狀態 |
|-------|------|
| nt0-rebrand-disconnect | PASS |
| nt1-real-graphics | PASS |
| nt2-real-light-games | PASS |
| nt3-real-launchers | PARTIAL（誠實） |
| nt4-anticheat-honest | PARTIAL（誠實） |

## 誠實邊界

- 預設 **native PE**；禁 Wine／Proton 底層
- 禁完整 Windows 相容／排位／官方 AC 簽章／3A 全開宣稱
- nt3／nt4 維持誠實 PARTIAL
- 與 StrawWU OS／ISO／桌面／kernel **無關**

## Hermes 驗收命令

```bash
test -f tests/strawnt/output/nt5-closeout.json
jq -e '.status == "PASS"' tests/strawnt/output/nt5-closeout.json
jq -e '.product == "StrawNT" or .name == "StrawNT"' tests/strawnt/output/nt5-closeout.json
rg -n 'StrawNT' README.md
```

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session／StrawWU 工作區
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows 相容／排位通過
