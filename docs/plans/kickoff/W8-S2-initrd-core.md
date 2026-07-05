# Wave 8 S2 — strawwu-live-init

| 任務 ID | w8-s2-initrd-core |
|---------|-------|
| Wave | 8 |
| 計畫 | `strawwu-initrd-plan.md` |
| 狀態 | 待執行 |

## 目標

fork casper 核心

## 必讀

- `docs/plans/strawwu-initrd-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-initrd-core
make preflight-iso-before-boot
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/W8-S2-initrd-core-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動 **w8-s3-initrd-bottom**（勿問使用者）。
