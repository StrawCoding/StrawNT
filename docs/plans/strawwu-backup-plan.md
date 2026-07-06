# StrawWU 系統備份（時光機）

| 版本 | 1.0 |
|------|-----|
| 對照維度 | H13 備份/時光機（Mint Timeshift） |
| Stage | `post-backup-timeshift` |

## 目標

1. `strawwu-backup` deb：Timeshift 整合或 Btrfs snapshot CLI 包裝
2. Hub「備份與還原」分頁骨架
3. 與 `post-upg-rollback` snapshot hook 對接

## 驗收

`make test-backup-timeshift` + stage report
