# U26-M5-techrefs-refresh

| 任務 ID | u26-m5-techrefs-refresh |
|---------|-------|
| 計畫 | `strawwu-ubuntu-2604-migration-plan.md` |

## 目標

見 `docs/plans/strawwu-ubuntu-2604-migration-plan.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-techrefs-refresh
make preflight
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/U26-M5-techrefs-refresh-report.md`
3. VERSION bump（`scripts/bump-version.sh`）

## 禁止

- SKIP_SQUASHFS=1 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS
- 複製 legacy 封存程式碼

## 完成後

Hermes mark PASS → 自動啟動下一 stage（勿問使用者）。
