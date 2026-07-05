# Wave 3 B3 — strawwu-update-notifier

| 任務 ID | w3-b3-update-notifier |
|---------|-------|
| Wave | 3 |
| 計畫 | `strawwu-ubuntu-components-plan.md` |
| 狀態 | 待執行 |

## 目標

取代 update-notifier

## 必讀

- `docs/plans/strawwu-ubuntu-components-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-update-notifier
make preflight
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/W3-B3-update-notifier-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動 **w3-n2-target-setup**（勿問使用者）。
