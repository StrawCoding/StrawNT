# Wave 5 — GDM/Greeter/Session

| 任務 ID | w5-grt-session |
|---------|-------|
| Wave | 5 |
| 計畫 | `strawwu-greeter-session-plan.md` |
| 狀態 | 待執行 |

## 目標

strawwu greeter 主題

## 必讀

- `docs/plans/strawwu-greeter-session-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-greeter-session
make preflight
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/W5-GRT-session-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS

## 延後範圍（勿擴 scope）

見 `strawwu-deferred-scope.md` §1：**v0.5 單使用者 GDM 登入**；不做 fast user switching / 家庭帳號 UI。

## 完成後

Hermes mark PASS → 自動啟動 **w6-n5-install-e2e**（勿問使用者）。
