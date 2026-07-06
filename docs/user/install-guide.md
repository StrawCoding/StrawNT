# StrawWU 安裝與首次設定指南

本指南說明從 Live USB 試用到完成安裝與首次設定（firstboot）的流程。適用於 StrawWU v0.5 預發布。

## 1. 系統需求

| 項目 | 建議 |
|------|------|
| 架構 | amd64（x86_64） |
| 記憶體 | ≥ 4 GiB（安裝建議 8 GiB） |
| 磁碟 | ≥ 32 GiB 可用空間（建議獨立分割區） |
| 韌體 | UEFI 或 Legacy BIOS 皆可（release-iso 驗收涵蓋兩者） |
| 顯示 | 支援 1920×1080 以上桌面環境 |

硬體相容性分級與 CI 代理矩陣見 `docs/plans/strawwu-hardware-compatibility-test-matrix.md`。

## 2. 製作 Live USB

### 2.1 下載 ISO

取得 `StrawWU-<版本>-amd64.iso`。可選驗證 `SHA256SUMS`（發佈管線產物，路徑見 `os-image/output/`）。

### 2.2 寫入隨身碟

任選一種方式（實機驗證建議三種皆試，見硬體矩陣計畫）：

| 工具 | 平台 | 備註 |
|------|------|------|
| **Rufus** | Windows | 選 DD 或 ISO 模式；UEFI 優先 |
| **dd** | Linux / macOS | `sudo dd if=StrawWU-*.iso of=/dev/sdX bs=4M status=progress conv=fsync` |
| **Ventoy** | 跨平台 | 複製 ISO 至 Ventoy 資料分割區 |

**注意：** 確認目標裝置代號正確，`dd` 會覆寫整顆隨身碟。

### 2.3 開機

1. 在韌體選單啟用 USB 開機（或暫時 Boot Menu）。
2. 選擇 **StrawWU Live**（或同等標題的 Live 項目）。
3. 等待 Plymouth 與桌面載入；Live 環境可試用瀏覽器、Flathub 等，**尚未寫入硬碟**。

### 2.4 Live 環境快速檢查（選用）

在已開機的 Live session 可執行硬體 smoke（開發者／進階使用者）：

```bash
sudo /path/to/smoke-live.sh --output /tmp/live-smoke.json --environment physical
```

腳本位於發行版 `tests/hw/smoke-live.sh`；檢查 session、網路、音效與 StrawWU branding。結果可合併至 `hw-matrix-results.json`（見 W6-HW1 報告）。

## 3. 安裝 StrawWU

### 3.1 啟動安裝程式

在 Live 桌面：

1. 開啟應用程式選單，選擇 **安裝 StrawWU**（`strawwu-install.desktop`）。
2. Calamares 安裝精靈啟動（StrawWU 品牌主題，非 Ubuntu 預設）。

### 3.2 安裝步驟概要

| 步驟 | 說明 |
|------|------|
| 語言與鍵盤 | 預設含繁體中文與英文 |
| 分割區 | 可整碟或自訂；**保留 /home** 選項於重裝時建議勾選 |
| 使用者帳號 | 建立本機使用者與密碼 |
| 安裝 | 複製系統檔並執行 target-setup hook |

安裝過程會透過 `strawwu-target-setup` 在 chroot 內安裝 meta 套件（desktop、bug-reporter、firstboot、flathub 等）。

### 3.3 完成畫面

安裝成功時顯示（繁中／英文對照見 `finished-copy.yaml`）：

> 全部完成。StrawWU 已安裝至您的電腦。您可立即重新開機進入新系統，或繼續使用 Live 環境。

可勾選 **完成後立即重新開機**。

### 3.4 安裝失敗

若安裝未完成：

1. 查看 `/var/log/installation.log`（Live 環境）。
2. 使用 **StrawWU 問題回報**（`strawwu-bug-report-gtk`）產生本機除錯套件（預設不上傳，需明確同意）。
3. 必要時參閱 [rescue-guide.md](rescue-guide.md) 修復已部分寫入的系統。

## 4. 首次開機與 firstboot 精靈

重新開機進入已安裝系統後，首次登入會啟動 **strawwu-firstboot** 六步精靈：

| 步驟 | 內容 |
|------|------|
| welcome | 歡迎 |
| language | 語系（zh_TW / en_US） |
| privacy | 隱私權與 EULA 摘要 |
| flathub | Flathub 遠端與範例應用 |
| desktop | 桌面偏好 |
| finish | 完成並寫入 lifecycle |

狀態記錄於 `/var/lib/strawwu/setup/` 與 `strawwu-initd` lifecycle。日誌：`/var/log/strawwu/firstboot.log`。

完成後精靈不再自動顯示。若需手動重跑（救援情境）見 [rescue-guide.md](rescue-guide.md)。

## 5. 安裝後驗證（使用者可選）

| 檢查 | 預期 |
|------|------|
| `strawwu --version` 或 Hub「關於」 | 顯示 StrawWU 版本 |
| Flathub | Hub 或 `flatpak remote-list` 含 flathub |
| 更新通知 | `strawwu-update-notifier` 取代 Ubuntu update-notifier |
| Windows 相容 | Hub「Windows 相容」分頁（啟動器級別，見 PRD Q8） |

## 6. 常見問題

**Q：可以只試用不安裝嗎？**  
A：可以。Live 環境完整可用，重開機前資料不寫入硬碟（除非您手動掛載並修改）。

**Q：與 Ubuntu 雙系統？**  
A：Calamares 分割區步驟可保留既有系統；請先備份重要資料。

**Q：安裝後 GRUB 沒有 StrawWU？**  
A：UEFI 機器請確認 ESP 掛載正確；必要時從 Live ISO 執行 `efibootmgr` 或 chroot 修復（見救援指南）。

**Q：哪裡取得更多說明？**  
A：官方支援渠道 **TBD**（v1.0）；目前請使用 Hub 問題回報。

## 7. 相關文件

- [rescue-guide.md](rescue-guide.md) — Live 救援與狀態修復
- [README.md](README.md) — 文件索引
- `docs/iso-modes.md` — ISO 建置模式（開發者）
