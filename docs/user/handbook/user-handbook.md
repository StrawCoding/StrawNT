# StrawWU 使用者手冊

本手冊說明安裝完成並通過首次設定（firstboot）後的**日常使用**。安裝流程見 [install-guide.md](../install-guide.md)。

## 1. 桌面環境概覽

StrawWU 桌面以 **strawwu-shell** 為預設工作階段（取代上游 GNOME Shell 品牌體驗），搭配 **strawwu-greeter** 登入畫面與 StrawWU 品牌主題（Plymouth、GRUB）。

| 元件 | 說明 |
|------|------|
| strawwu-shell | 內建 Dock、應用程式選單、系統匣 |
| strawwu-hub | 設定中心、應用程式管理、Flathub、Windows 相容狀態 |
| strawwu-session | 預設 X11/Wayland session 與 autostart |
| fcitx5 | 預設輸入法框架（繁體中文、注音等） |

登入後若首次設定未完成，會自動啟動 **strawwu-firstboot** 六步精靈（語言、鍵盤、隱私、Flathub、更新、完成）。

## 2. StrawWU Hub

從 Dock 或應用程式選單開啟 **StrawWU Hub**（`strawwu-hub`）。

### 2.1 設定

Hub「設定」整合系統偏好：顯示、音效、網路、電源、使用者帳號等。部分進階項目仍導向 GNOME 設定面板（upstream 相容層）。

### 2.2 應用程式（Apps）

「應用程式」頁面顯示 **User App Registry** 中已登記的程式：

- Linux 原生 `.desktop` 應用
- Flatpak（Flathub 與其他 remote）
- Windows 相容層安裝的應用（見 [wincompat-guide.md](wincompat-guide.md)）

可從此頁啟動、移除（deep uninstall）或查看來源。右鍵桌面圖示亦可「從桌面移除」並同步 favorites。

### 2.3 Flathub

Hub「Flathub」提供瀏覽與安裝 Flatpak 應用的 MVP 介面。系統已預設 `flathub` remote（`strawwu-flatpak-setup`）。安裝後會透過 registry hooks 自動掃描登記。

### 2.4 Windows 相容

Hub「Windows 相容」顯示 `strawwu status` 摘要與 compat-db 等級。詳見 [wincompat-guide.md](wincompat-guide.md)。

### 2.5 關於

「關於」顯示 StrawWU 版本、授權與**回報問題**入口（`strawwu-bug-report-gtk`）。

## 3. 安裝與移除應用程式

### 3.1 Linux 原生

- **APT**：`sudo apt install <套件>`（StrawWU 官方倉庫 + Ubuntu base，見管理員手冊）
- 安裝後 `strawwu-app-registry` 透過 hooks 掃描 `.desktop` 並登記

### 3.2 Flatpak

- Hub Flathub 頁面，或終端：`flatpak install flathub <app-id>`
- 移除：Hub Apps 頁 deep uninstall，或 `flatpak uninstall`

### 3.3 Windows 應用

使用 `strawwu` CLI 或 Hub 引導安裝 `.exe`／啟動器。相容等級與限制見 [wincompat-guide.md](wincompat-guide.md)。

> **v0.5 誠實邊界：** Office、Steam、Epic、三角洲等「黃金應用」啟動器驗收屬 Q8 路線；不保證所有 Windows 軟體可正常運作。

## 4. 語言與輸入法

| 項目 | 預設 |
|------|------|
| 系統語系 | 繁體中文（zh_TW）為主，英文對照 |
| 輸入法 | fcitx5 + 注音／倉頡等 |
| IME 切換 | 依 fcitx5 設定（通常 Super+Space 或 Ctrl+Space） |

首次設定精靈可調整語言與鍵盤配置；後續於 Hub 設定或 `gnome-control-center` 修改。

## 5. 系統更新

**strawwu-update-notifier** 取代上游 update-notifier，在可用更新時通知使用者。更新來源：

- Ubuntu security/base（有限 allowlist，見 meta-audit）
- StrawWU 官方 APT 倉庫（`strawwu-keyring` 簽章）

建議定期套用更新；重大升級前請參閱 [upgrade-rescue-guide.md](upgrade-rescue-guide.md)。

## 6. 問題回報

1. Hub「關於」→ **回報問題**，或終端執行 `strawwu-bug-report-gtk`。
2. 依精靈選擇是否附帶系統資訊（需使用者同意，符合隱私政策）。
3. 產生本機 bundle；v0.5 自動上傳管道 **TBD**。

日誌路徑：`/var/log/strawwu/`、`/var/lib/strawwu/`。請勿在公開場合分享含個人資料的 bundle。

## 7. 常見情境

| 情境 | 建議 |
|------|------|
| 桌面圖示遺失 | Hub Apps → 重新釘選；或 `strawwu-app-registry scan` |
| Flatpak 無法啟動 | `flatpak repair`；確認 flathub remote |
| Windows 應用無法啟動 | `strawwu status`；查 [wincompat-guide.md](wincompat-guide.md) 等級 |
| 系統無法開機 | [rescue-guide.md](../rescue-guide.md) |
| 升級後異常 | [upgrade-rescue-guide.md](upgrade-rescue-guide.md) |

## 8. 支援渠道

| 管道 | 狀態 |
|------|------|
| 內建 bug-reporter | 可用 |
| 官方論壇 / Matrix / Discord | **TBD** |
| 支援網址 | **TBD** — `https://strawwu.local/support` |

## 9. 相關文件

- [install-guide.md](../install-guide.md) — 安裝與 firstboot
- [wincompat-guide.md](wincompat-guide.md) — Windows 相容分級
- [upgrade-rescue-guide.md](upgrade-rescue-guide.md) — 升級與 rollback
- [admin-handbook.md](admin-handbook.md) — 管理員維運（進階）
