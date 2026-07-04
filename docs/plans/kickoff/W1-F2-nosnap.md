# Wave 1 — F2 移除 Snap meta

| 任務 ID | W1-F2-nosnap |
|---------|--------------|
| 版本 | 1.0 |
| 日期 | 2026-07-04 |
| 狀態 | 待啟動 |

## 目標

確認 snapd 已完全移除；desktop meta 不再依賴 snap；preflight 驗證 snap 零殘留。

## 範圍

### 必須交付

1. 審計 rootfs meta 套件（`ubuntu-desktop` 等）snap 依賴 — 文件化或 mask
2. 確保 `/snap` 不存在或為空 stub
3. 更新 preflight / release-baseline
4. `docs/plans/stage-reports/W1-F2-nosnap-report.md`
5. VERSION bump（若有變更）

## PASS 條件

```bash
make test-purge-baseline   # snapd absent
make test-flatpak          # flathub still OK
make preflight
```

## 禁止

- 重新引入 snapd
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動 W1-S1-initrd。
