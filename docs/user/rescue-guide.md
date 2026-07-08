# StrawWU 救援與修復指南

本指南說明當已安裝系統無法正常開機、設定損毀或安裝中斷時的**救援**流程。v0.7 起提供 `strawwu-upgrade --rollback` 與 Live ISO「StrawWU Rescue」GRUB 項目；本文件涵蓋基礎 chroot 修復與升級回滾。

## 1. 何時使用本指南

| 情境 | 建議路徑 |
|------|----------|
| 安裝到一半失敗 | Live USB → 檢查 log → 重裝或修復分割區 |
| 開機進 GRUB 但 kernel panic | GRUB 選單選前一個 kernel entry（若存在） |
| 桌面無法登入 / firstboot 迴圈 | Live → chroot → `strawwu-initd repair` |
| meta 套件遺失 / registry 損毀 | Live → chroot → `strawwu-target-setup --repair-only` |
| 僅需收集除錯資訊 | Live 或已安裝系統執行 `strawwu-bug-report-gtk` |

## 2. 從 Live ISO 進入救援

1. 使用 **StrawWU Live USB** 開機。
2. 在 GRUB 選單選擇 **StrawWU Rescue**（或標準 Live 項目）。
3. Rescue 模式會在桌面顯示提示；開啟終端機執行 chroot 修復。

> **v0.7：** ISO 已含專用「StrawWU Rescue」GRUB 項目（`strawwu_rescue=1`）。亦可使用標準 Live 項目掛載已安裝分割區。

## 3. 掛載已安裝系統

假設根分割區為 `/dev/sda2`、EFI 為 `/dev/sda1`（請依 `lsblk` 調整）：

```bash
sudo mkdir -p /mnt/strawwu
sudo mount /dev/sda2 /mnt/strawwu

# UEFI 系統
sudo mkdir -p /mnt/strawwu/boot/efi
sudo mount /dev/sda1 /mnt/strawwu/boot/efi

# 綁定 chroot 所需 pseudo-fs
sudo mount --bind /dev  /mnt/strawwu/dev
sudo mount --bind /proc /mnt/strawwu/proc
sudo mount --bind /sys  /mnt/strawwu/sys
sudo mount --bind /run  /mnt/strawwu/run
```

進入 chroot：

```bash
sudo chroot /mnt/strawwu /bin/bash
```

## 4. 修復指令

### 4.1 strawwu-initd repair

修復 `state.json` 與 lifecycle 旗標（備份損毀檔後重新初始化）：

```bash
strawwu-initd repair
```

適用：firstboot 狀態不一致、JSON 損毀、升級後 lifecycle 異常。

### 4.2 strawwu-target-setup --repair-only

重新套用 target manifest 中的 staged deb（desktop meta、bug-reporter、firstboot 等）：

```bash
strawwu-target-setup --repair-only
```

適用：Calamares 安裝中斷後 meta 不完整、手動刪除 StrawWU 套件後需還原。

### 4.3 重設 firstboot（進階）

若需讓首次設定精靈再次執行（會覆寫使用者偏好，請謹慎）：

```bash
strawwu-initd set lifecycle.firstboot_required=true
rm -f /var/lib/strawwu/setup/firstboot-prefs.json
```

登出後重新登入觸發 `strawwu-firstboot` autostart。

### 4.4 GRUB / UEFI 修復

在 chroot 內（已掛載 `/boot/efi`）：

```bash
update-grub
# UEFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=StrawWU
efibootmgr -v
```

**已知案例：** 部分 UEFI 環境需確保 `EFI/BOOT/grub.cfg` 與 `EFI/strawwu/grub.cfg` 一致（見 W6-I4 報告）。

## 5. 升級失敗與 rollback

| 能力 | v0.7 狀態 |
|------|-----------|
| 保留 ≥2 個 kernel | **部分** — snapshot 記錄 kernel 清單；GRUB 多 kernel 策略持續強化 |
| `initrd.img.old` symlink | **可用** — rollback 時還原 symlink |
| `strawwu-upgrade --rollback` | **可用** — 還原 pre-upgrade snapshot（state + boot 標記） |
| `strawwu-upgrade preflight` | **可用** — 升級前磁碟／state 檢查 |
| apt 失敗後手動 `apt install` 修復 | 可用 |
| Live chroot + repair 指令 | **可用（本指南）** |

升級失敗時優先嘗試：

```bash
# 已開機進系統
sudo strawwu-upgrade --rollback

# 或 Live Rescue → chroot 後
strawwu-upgrade --rollback
strawwu-initd repair
strawwu-target-setup --repair-only
```

詳見 [handbook/upgrade-rescue-guide.md](handbook/upgrade-rescue-guide.md)。

## 6. 問題回報與日誌

| 路徑 | 內容 |
|------|------|
| `/var/log/installation.log` | Calamares 安裝 |
| `/var/log/strawwu/firstboot.log` | 首次設定精靈 |
| `/var/lib/strawwu/` | state、registry、備份 |
| `strawwu-bug-report` | 產生本機 bundle（需 opt-in 上傳） |

Hub「關於」→ **回報問題** 啟動 GTK 回報器。社群支援 URL：**TBD**。

## 7. Live 硬體 smoke（實機驗證）

在 Live session 驗證開機與桌面是否正常：

```bash
bash tests/hw/smoke-live.sh --output /tmp/smoke.json --environment physical
```

將輸出合併至專案 `docs/plans/hw-matrix-results.json` 供相容性追蹤（維護者／Hermes 實機 session）。

## 8. 離開 chroot 與卸載

```bash
exit   # 離開 chroot
sudo umount -R /mnt/strawwu
```

重新開機並移除 USB。

## 9. 相關文件

- [install-guide.md](install-guide.md) — 正常安裝流程
- `docs/plans/strawwu-upgrade-recovery-plan.md` — 完整 UPG／rollback 路線圖
- [README.md](README.md) — 文件索引
