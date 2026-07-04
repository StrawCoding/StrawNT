# StrawWU AI Worker SOP（Hermes / Cursor 治理）

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 對齊 | 客人原則 v2.0、long-task-worker skill |

## 1. 任務命名

`[W<n>|S|I|N|B|F|D|R|W|RE|SEC|...]-<phase>-<slug>`

例：`W4-strawwu-shell-dock`、`N2-target-setup-hook`

## 2. Worker 範圍

| 允許 | 禁止 |
|------|------|
| 單一 Phase  scoped 目錄 | 跨 Wave 並行改同一 ISO |
| `components/`、`os-image/`、`docs/plans/` | 未授權改 `kernel/`（需 S/W 標籤） |
| tests + preflight | SKIP_SQUASHFS / 并行 boot-test 同一 ISO |

## 3. 硬性閘門

```
改碼 → preflight PASS → （release）boot-test → E2E
```

FAIL：Hermes 只回「測試失敗 + log 路徑」，不給修復方向。

## 4. 每次任務必須輸出

1. 變更檔案清單
2. 執行的測試命令 + PASS/FAIL
3. VERSION bump（若有源碼變更）
4. commit message（Conventional Commits）
5. 若 Phase 完成：更新 `docs/plans/` 或 stage-report

## 5. Commit 格式

```
feat(w4): add strawwu-shell dock stub

- ...
Tests: make test-desktop-stack PASS
Issue: Plane SWU-xxx (if any)
```

## 6. PR / closeout Checklist

- [ ] VERSION bumped
- [ ] preflight PASS
- [ ] 關聯測試 PASS
- [ ] 無 Ubuntu 商標 UI 回歸（LEG0 scan）
- [ ] Plane issue 註明版本號

## 7. 長任務

- tmux worker + companion supervisor
- 連續 FAIL >10 → 問使用者是否繼續
- 完成：Hermes commit + push + 部署驗證（不問確認）

## 8. Artifacts

| 類型 | 位置 |
|------|------|
| HTML 報告 | hermes-deliver → download.hermes.wastebase.xyz |
| test output | `tests/*/output/` |
| ISO | `os-image/output/`（不 commit） |
| hw matrix | `docs/plans/hw-matrix-results.json` |

## 9. 報告格式

- 繁中
- 深色 HTML、Teal 主色
- 誠實 PASS/PARTIAL/FAIL
- 含測試證據路徑
