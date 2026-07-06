# StrawWU 升級與救援指南

本指南（**DOC3**）說明系統升級失敗、rollback 規劃與救援流程的**誠實邊界**。基礎 Live chroot 救援見 [rescue-guide.md](../rescue-guide.md)；本文件聚焦升級情境與 UPG 路線圖。

## 1. 文件層級

| 層級 | 文件 | 涵蓋 |
|------|------|------|
| 基礎救援 | [rescue-guide.md](../rescue-guide.md) | Live USB、chroot、`initd repair`、`target-setup --repair-only` |
| 升級／rollback | 本文件 | UPG 規劃、`strawwu-upgrade`、kernel 保留策略 |
| 管理維運 | [admin-handbook.md](admin-handbook.md) | APT、發佈、initramfs |

## 2. v0.5 已實作能力

| 能力 | 狀態 | 說明 |
|------|------|------|
| Live + chroot 修復 | **可用** | 見 rescue-guide §3–§4 |
| `strawwu-initd repair` | **可用** | 狀態與 lifecycle 修復 |
| `strawwu-target-setup --repair-only` | **可用** | meta 套件還原 |
| GRUB 舊 kernel entry | **視安裝** | 若存在可手動選擇 |
| apt 失敗後手動修復 | **可用** | `apt install --fix-broken` 等 |
| `strawwu-bug-report` | **可用** | 收集升級失敗證據 |

## 3. v0.5 尚未實作（UPG 路線圖）

| 能力 | 規劃 | 說明 |
|------|------|------|
| `strawwu-upgrade --rollback` | UPG4+ | 一鍵回滾至前一版本 |
| 保留 ≥2 個 kernel | UPG4 | 升級失敗時 GRUB 回退 |
| `initrd.img.old` symlink | UPG | 搭配 kernel 保留 |
| 專用「StrawWU Rescue」GRUB 項目 | UPG5 | 目前使用標準 Live |
| Btrfs/ZFS snapshot rollback | 評估中 | 見 upgrade-recovery-plan |
| compat-db 升級後重建 | UPG | 保留 user profiles |

**請勿期待** v0.5 具備一鍵 rollback；升級前請備份重要資料。

## 4. 升級失敗處理流程

```
升級中斷或開機失敗
        │
        ├─► GRUB 有舊 kernel？ ──是──► 選舊 entry 開機 → apt 修復
        │
        └─► 否 ──► Live USB 開機
                    │
                    ├─► chroot → strawwu-initd repair
                    ├─► chroot → strawwu-target-setup --repair-only
                    ├─► apt update && apt install -f
                    └─► update-grub / grub-install（見 rescue-guide §4.4）
```

### 4.1 日誌位置

| 路徑 | 內容 |
|------|------|
| `/var/log/apt/history.log` | APT 升級記錄 |
| `/var/log/dpkg.log` | 套件解壓／設定 |
| `/var/log/strawwu/` | StrawWU 元件日誌 |
| `/var/lib/strawwu/setup/state.json` | lifecycle 狀態 |

### 4.2 收集證據

升級失敗時執行 `strawwu-bug-report-gtk`，附註升級前後版本與錯誤訊息。

## 5. 升級前建議（管理員）

1. 確認 `make preflight` 與目標版本 release-manifest 簽章。
2. 在測試機驗證 `release-iso` 安裝 → 升級路徑。
3. 備份 `/home` 與重要設定。
4. 記錄目前 `VERSION` 與已安裝 `strawwu-*` 套件版本（`dpkg -l 'strawwu-*'`）。

## 6. Live 救援與 UPG5

目前救援使用**標準 StrawWU Live USB**（與安裝相同 ISO），非獨立 Rescue 映像：

1. Live 開機 → 掛載根分割區（rescue-guide §3）
2. chroot 執行修復指令
3. UPG5 將新增專用 GRUB「StrawWU Rescue」項目與精簡救援環境

## 7. rollback 設計預覽（未實作）

依 `docs/plans/strawwu-upgrade-recovery-plan.md`：

- 升級前建立 snapshot 或保留前一 rootfs 標記
- `strawwu-upgrade --rollback` 還原 kernel + initrd + staged debs
- compat-db 重建並保留使用者 app profiles

實作完成後本文件將更新為操作步驟。

## 8. 與其他元件的關聯

| 元件 | 升級／救援角色 |
|------|----------------|
| strawwu-initramfs-hooks | 升級後確保磁碟 initrd 無 casper |
| strawwu-target-identity | 升級後 GRUB／Plymouth 品牌一致 |
| strawwu-keyring | APT 來源簽章驗證 |
| strawwu-update-notifier | 通知可用更新（非自動升級 major） |

## 9. 相關文件

- [rescue-guide.md](../rescue-guide.md) — 基礎救援步驟
- [admin-handbook.md](admin-handbook.md) — APT 與發佈
- [user-handbook.md](user-handbook.md) §5 系統更新
- `docs/plans/strawwu-upgrade-recovery-plan.md` — 完整 UPG 規格
