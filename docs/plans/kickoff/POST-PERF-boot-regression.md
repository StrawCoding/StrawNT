# POST-PERF-boot-regression

| 任務 ID | post-perf-boot-regression |
|---------|-------|
| 計畫 | `strawwu-performance-budget-plan.md` |
| 對照 | 對比書 H5 |

## 目標

開機時間 baseline + nightly CI 回歸閾值（PERF2）

## PASS 條件

```bash
make test-perf-boot-regression
make preflight
```

## 必須交付

1. PERF2 gate 腳本/基線 JSON
2. `docs/plans/stage-reports/POST-PERF-boot-regression-report.md`
