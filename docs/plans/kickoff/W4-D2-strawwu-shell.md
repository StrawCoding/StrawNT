# Wave 4 D2 — strawwu-shell

| 任務 ID | w4-d2-strawwu-shell |
|---------|-------|
| Wave | 4 |
| 計畫 | `strawwu-desktop-plan.md` |
| 狀態 | 待執行 |

## 目標

GNOME Shell fork + 內建 Dock

## 必讀

- `docs/plans/strawwu-desktop-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-strawwu-shell
make preflight
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/W4-D2-strawwu-shell-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS

## 延後範圍（勿擴 scope）

見 `strawwu-deferred-scope.md` §5：**v0.5 不做插件 API / extension 載入**；僅 fork + 內建 Dock。

## 完成後

Hermes mark PASS → 自動啟動 **w4-d3-hub-settings**（勿問使用者）。
