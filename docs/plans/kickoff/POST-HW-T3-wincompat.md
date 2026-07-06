# Post-MVP — HW T3 wincompat

| 任務 ID | post-hw-t3-wincompat |
|---------|-------|
| Track | Post-MVP |
| 計畫 | `strawwu-hardware-compatibility-test-matrix.md` |
| 路線圖 | `strawwu-post-mvp-roadmap.md` |

## 目標

Win compat 實機 smoke

## 必讀

- `docs/plans/strawwu-post-mvp-roadmap.md`
- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-hardware-compatibility-test-matrix.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-hw-t3-wincompat
make preflight
# exit 0
```

## 必須交付

1. 本階段實作產物（見計畫文件）
2. `docs/plans/stage-reports/POST-HW-T3-wincompat-report.md`
3. VERSION bump（`scripts/bump-version.sh`）
4. 對應 preflight 腳本（若尚不存在）

## 禁止

- 修改 `kernel/` 源碼（除非本 stage 明確要求）
- `SKIP_SQUASHFS=1` 進 release 驗收
- 并行 boot-test 寫同一 ISO
- worker 自宣稱 PASS
- 複製 legacy 封存程式碼

## 完成後

Hermes mark PASS → 自動啟動下一 Post-MVP stage（勿問使用者）。
