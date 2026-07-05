# Wave 6 DOC1 — 使用者文件

| 任務 ID | w6-doc1-user-docs |
|---------|-------|
| Wave | 6 |
| 計畫 | `strawwu-user-docs-plan.md` |
| 狀態 | 待執行 |

## 目標

安裝/rescue 文件

## 必讀

- `docs/plans/strawwu-user-docs-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-user-docs
make preflight
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/W6-DOC1-user-docs-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS

## 延後範圍（勿擴 scope）

見 `strawwu-deferred-scope.md` §4：**社群/支援渠道佔位即可**（TBD 連結）；不阻擋本 stage PASS。

## 完成後

Hermes mark PASS → 自動啟動 **w7-re-manifest-gpg**（勿問使用者）。
