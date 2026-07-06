# FORK-F3-build-pipeline

| 任務 ID | fork-f3-build-pipeline |
|---------|-------|
| 計畫 | `strawwu-fork-migration-plan.md` |

## 目標

見 `docs/plans/strawwu-fork-migration-plan.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f3-build-pipeline
make preflight
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/FORK-F3-build-pipeline-report.md`
3. VERSION bump（`scripts/bump-version.sh`）

## 禁止

- 中斷 u26-m6 進行中的 worker
- SKIP_SQUASHFS=1 進 release 驗收
- 复制 legacy 封存程式碼
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動下一 stage（勿問使用者）。
