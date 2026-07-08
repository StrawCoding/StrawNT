# StrawWU 升級與救援指南

本指南（**DOC3**）說明系統升級、snapshot rollback 與救援流程。基礎 Live chroot 救援見 [rescue-guide.md](../rescue-guide.md)。

## 1. 文件層級

| 層級 | 文件 | 涵蓋 |
|------|------|------|
| 基礎救援 | [rescue-guide.md](../rescue-guide.md) | Live USB、chroot、`initd repair`、`target-setup --repair-only` |
| 升級／rollback | 本文件 | UPG 規劃、`strawwu-upgrade`、kernel 保留策略 |
| 管理維運 | [admin-handbook.md](admin-handbook.md) | APT、發佈、initramfs |

## 2. v0.7 已實作能力

| 能力 | 狀態 | 說明 |
|------|------|------|
| Live + chroot 修復 | **可用** | 見 rescue-guide §3–§4 |
| `strawwu-initd repair` | **可用** | 狀態與 lifecycle 修復 |
| `strawwu-target-setup --repair-only` | **可用** | meta 套件還原 |
| `strawwu-upgrade preflight` | **可用** | 磁碟空間、state.json 檢查 |
| `strawwu-upgrade snapshot` | **可用** | `/var/lib/strawwu/backups/pre-upgrade-<ver>` |
| `strawwu-upgrade --rollback` | **可用** | 還原 snapshot（state + initrd.old） |
| 專用「StrawWU Rescue」GRUB 項目 | **可用** | Live ISO，`strawwu_rescue=1` |
| `strawwu-bug-report` | **可用** | 收集升級失敗證據 |

## 3. 尚未完整實作（後續 UPG）

| 能力 | 規劃 | 說明 |
|------|------|------|
| 保留 ≥2 個 kernel（自動） | UPG4 | 升級失敗時 GRUB 回退強化 |
| Btrfs/ZFS snapshot rollback | 評估中 | 見 upgrade-recovery-plan |
| compat-db 升級後自動重建 | UPG | 保留 user profiles |
| 無人值守 major 升級 | v1.0 | 需備份提示與 migration hooks |

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

## 6. Live 救援（StrawWU Rescue）

Live ISO 提供專用 **StrawWU Rescue** GRUB 項目（`strawwu_rescue=1`）：

1. Rescue 開機 → 桌面顯示救援提示
2. 掛載根分割區（rescue-guide §3）
3. chroot 執行 `strawwu-upgrade --rollback`、`strawwu-initd repair`、`strawwu-target-setup --repair-only`

標準 Live 項目亦可用于相同 chroot 流程。

## 7. rollback 操作步驟

```bash
# 升級前（建議）
sudo strawwu-upgrade preflight
sudo strawwu-upgrade snapshot

# 升級（乾跑測試）
sudo strawwu-upgrade upgrade --dry-run

# 升級失敗回滾
sudo strawwu-upgrade --rollback
sudo strawwu-initd repair
sudo strawwu-target-setup --repair-only
```

Snapshot 儲存於 `/var/lib/strawwu/backups/pre-upgrade-<version>/`，含 `state.json` 與 `manifest.json`。

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
