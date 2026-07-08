# StrawWU 系統更新使用手冊

本手冊說明安裝完成後如何更新 StrawWU 系統與應用程式。適用版本：StrawWU 1.0.0.0 及之後（基底 Ubuntu 26.04 LTS Resolute Raccoon）。

升級失敗與救援流程見 [upgrade-rescue-guide.md](upgrade-rescue-guide.md)。

## 1. 更新方式總覽

StrawWU 的系統更新分為三條路徑：

| 類型 | 方式 | 內容 |
|------|------|------|
| 日常小更新 | Hub 或 `apt upgrade` | 安全修補、套件小版本、strawwu-* 元件更新 |
| 重大版本升級 | `strawwu-upgrade` | 跨大版本（如 0.6 → 1.0），含 snapshot 與 rollback |
| 應用程式 | Flatpak / Hub Apps | Flathub 與已安裝應用，獨立於系統核心更新 |

```
日常安全更新 ──► apt / Hub「軟體源」→「檢查更新」
重大版本升級 ──► strawwu-upgrade preflight → snapshot → upgrade
Flatpak 應用   ──► flatpak update 或 Hub Apps 頁面
```

## 2. 日常更新（APT / Hub）

### 2.1 StrawWU Hub（圖形介面，推薦）

1. 從 Dock 或應用程式選單開啟 **StrawWU Hub**
2. 進入左側 **「軟體源」** 分頁
3. 按 **「檢查更新」**
4. 若有可用更新，依畫面提示套用（會透過 APT 安裝）

Hub 會顯示「有 N 個可用更新」或「系統已是最新狀態」。唯讀軟體源（Flathub、Ubuntu 安全性更新）無法停用，確保基本安全修補持續可用。

### 2.2 終端機

```bash
sudo apt update
sudo apt upgrade
```

若需一併處理相依變更（例如核心版本切換）：

```bash
sudo apt update
sudo apt full-upgrade
```

### 2.3 更新來源

| 來源 | 內容 | 簽章 |
|------|------|------|
| **StrawWU 官方 APT** (`https://apt.strawwu.org`) | 全部 `strawwu-*` 自製套件、meta 套件、驅動策展 | `strawwu-keyring` GPG 驗證 |
| **Ubuntu 安全性更新**（有限 allowlist） | 核心安全修補、基礎系統函式庫 | Ubuntu 官方簽章 |
| **Flathub** | Flatpak 應用（獨立更新通道） | Flathub 簽章 |

APT suite 名稱：`resolute`（對應 Ubuntu 26.04 LTS）。元件：`main`，架構：`amd64`。

## 3. 更新通道

Hub 左側 **「更新通道」** 分頁可選擇 StrawWU 官方套件的發布節奏。變更後將在**下次更新檢查**時生效。

| 通道 | 說明 | 適合對象 |
|------|------|----------|
| **Stable**（推薦） | 穩定版 — 經過完整測試的正式版本，含 SHA256 + GPG 簽章 | 一般使用者、生產環境 |
| **Beta** | 測試版 — 包含即將發布的新功能，preview 標記 | 願意搶先體驗新功能的使用者 |
| **Nightly** | 每日建置 — 最新但可能不穩定，僅供開發者 | 開發者、測試人員 |

> 切換通道**不會**自動升級系統；需手動在「軟體源」按「檢查更新」或執行 `apt update` 後才會看到新通道的套件。

## 4. 軟體源管理

Hub「軟體源」分頁可檢視與管理 APT 來源。部分來源為**唯讀**（不可停用），以確保系統安全。

| 軟體源 | 類型 | 可切換 | 說明 |
|--------|------|--------|------|
| StrawWU 官方 | APT | 是 | 自製套件與 meta 套件 |
| Ubuntu 安全性 | APT | 唯讀 | 有限 allowlist 的安全修補 |
| Flathub | Flatpak | 唯讀 | 預設 Flatpak 應用來源 |
| 第三方 APT | APT | 是（需管理員驗證） | 使用者自行新增的來源 |

終端機查詢軟體源狀態：

```bash
strawwu-software-sources status
strawwu-software-sources check-updates
```

## 5. 更新通知

StrawWU 以 **strawwu-update-notifier** 取代 Ubuntu 的 `update-notifier`，登入後背景執行：

- 偵測到可用更新時，顯示**桌面通知**
- 升級前顯示提醒：**「升級前請先備份」**（繁中）
- APT 操作後透過 hook 觸發重新檢查（`99strawwu-update-notifier`）
- **不會**自動執行 major 大版本無人值守升級

手動觸發檢查：

```bash
strawwu-update-notifier check
```

日誌位置：`/var/log/strawwu/update.log`

## 6. 重大版本升級

跨大版本（例如 0.6.x → 1.0.0）請使用 **strawwu-upgrade**，內建升級前檢查、snapshot 與 rollback，不要只靠 `apt dist-upgrade`。

### 6.1 建議流程

```bash
# 1. 升級前檢查（磁碟空間、state.json 等）
sudo strawwu-upgrade preflight

# 2. 建立還原點
sudo strawwu-upgrade snapshot
# 還原點位置：/var/lib/strawwu/backups/pre-upgrade-<版本>/

# 3. 乾跑測試
sudo strawwu-upgrade upgrade --dry-run

# 4. 正式升級
sudo strawwu-upgrade upgrade
```

`strawwu-upgrade upgrade` 會自動依序執行：preflight 檢查 → 建立 snapshot → APT dist-upgrade。任一步驟失敗會中止並保留 rollback 路徑。

### 6.2 指令參考

| 指令 | 用途 |
|------|------|
| `strawwu-upgrade preflight` | 檢查磁碟空間、lifecycle state、套件就緒狀態 |
| `strawwu-upgrade snapshot` | 建立升級前還原點（含 state.json + manifest） |
| `strawwu-upgrade upgrade` | 完整升級流程 |
| `strawwu-upgrade upgrade --dry-run` | 模擬升級，不修改系統 |
| `strawwu-upgrade rollback` | 還原至最新 pre-upgrade snapshot |
| `strawwu-upgrade list-snapshots` | 列出既有還原點 |
| `strawwu-upgrade --json` | 輸出機器可讀 JSON（腳本整合用） |

## 7. Flatpak 應用更新

Flatpak 應用與系統核心更新**獨立**，需另外更新。

```bash
flatpak update
```

StrawWU Hub：

- **Apps** 分頁 — 管理已安裝應用（啟動、移除）
- **Flathub** 分頁 — 瀏覽與安裝新應用

Flatpak 無法啟動時可嘗試修復：

```bash
flatpak repair
flatpak remote-list    # 確認 flathub remote 存在
```

## 8. 備份與還原

重大升級前強烈建議備份。StrawWU 提供兩層備份機制：

| 機制 | 位置 / 指令 | 用途 |
|------|-------------|------|
| 升級前 snapshot | `strawwu-upgrade snapshot` / `/var/lib/strawwu/backups/pre-upgrade-*` | 升級失敗時 rollback |
| Hub 備份分頁 | Hub →「備份與還原」 | rsync / Btrfs / Timeshift 系統快照 |

Hub 備份操作：

1. 開啟 Hub → **「備份與還原」**
2. 按 **「建立快照」** 建立系統快照
3. 升級前快照會自動與 `strawwu-upgrade snapshot` 共用同一 backup root
4. 需要時按 **「預覽還原」** 查看還原計畫

> 建議重大升級前同時做：**Hub 備份**（保護 /home 與個人資料）+ **strawwu-upgrade snapshot**（保護系統狀態與 lifecycle）。

## 9. 升級失敗與救援

升級失敗處理流程：

```
升級中斷或開機失敗
    │
    ├─► GRUB 有舊 kernel？ ──是──► 選舊 entry 開機 → apt 修復
    │
    └─► 否 ──► Live USB 開機
                │
                ├─► 選「StrawWU Rescue」GRUB 項目
                ├─► chroot → strawwu-upgrade rollback
                ├─► chroot → strawwu-initd repair
                ├─► chroot → strawwu-target-setup --repair-only
                └─► apt update && apt install -f
```

Rollback 指令：

```bash
sudo strawwu-upgrade rollback
sudo strawwu-initd repair
sudo strawwu-target-setup --repair-only
```

詳見 [upgrade-rescue-guide.md](upgrade-rescue-guide.md)。

### 9.1 日誌與證據收集

| 路徑 | 內容 |
|------|------|
| `/var/log/apt/history.log` | APT 升級記錄 |
| `/var/log/dpkg.log` | 套件解壓與設定 |
| `/var/log/strawwu/update.log` | StrawWU 更新通知日誌 |
| `/var/log/strawwu/` | 其他 StrawWU 元件日誌 |
| `/var/lib/strawwu/setup/state.json` | lifecycle 狀態 |

升級失敗時執行 `strawwu-bug-report-gtk` 收集證據，並附註升級前後版本。

## 10. 常見問題

**Q：多久該更新一次？**

建議每 1～2 週檢查一次安全更新。有桌面通知時盡快套用安全修補；功能更新可擇時進行。

**Q：更新會重開機嗎？**

若更新包含**核心（kernel）**或底層驅動，需要重開機才會生效。Hub / apt 完成後若提示 reboot，請存檔後重開。

**Q：可以只更新 StrawWU 元件、不更新 Ubuntu 基底嗎？**

日常 `apt upgrade` 會同時處理已啟用來源中的套件。Ubuntu 安全性來源為唯讀且建議保持啟用。若只想確認 strawwu 套件：

```bash
apt list --upgradable 2>/dev/null | grep strawwu
```

**Q：Stable 和 Beta 可以隨時切換嗎？**

可以，在 Hub「更新通道」切換後，下次「檢查更新」即會對應新通道。不建議在生產環境長期使用 Nightly。

**Q：無人值守自動大版本升級何時支援？**

規劃於 v1.0 提供，需搭配備份提示與 migration hooks。目前 major 升級需手動執行 `strawwu-upgrade`。

## 11. 速查表

| 我想… | 這樣做 |
|--------|--------|
| 平常補安全更新 | Hub → 軟體源 → 檢查更新；或 `sudo apt update && sudo apt upgrade` |
| 換 Beta / Nightly 通道 | Hub → 更新通道 → 選擇後再檢查更新 |
| 大版本升級 | `strawwu-upgrade preflight` → `snapshot` → `upgrade` |
| 升級搞壞了 | `strawwu-upgrade rollback`；或 Live USB → StrawWU Rescue |
| 更新 Flatpak 軟體 | `flatpak update` |
| 升級前備份 | Hub → 備份與還原 → 建立快照 |
| 看更新日誌 | `/var/log/strawwu/update.log` |
| 回報升級問題 | `strawwu-bug-report-gtk` |

## 12. 目前能力邊界（誠實標示）

| 能力 | 狀態 |
|------|------|
| 日常 APT 安全 / 套件更新 | 可用 |
| Hub 檢查更新 + 通道切換 | 可用 |
| 升級前備份提醒 | 可用 |
| strawwu-upgrade + rollback | 可用 |
| StrawWU Rescue GRUB 項目 | 可用 |
| Hub 備份 / Timeshift 整合 | 可用 |
| 無人值守 major 自動升級 | 規劃 v1.0 |
| Btrfs / ZFS 一鍵 snapshot rollback | 評估中 |
| 自動保留 ≥2 個 kernel 回退 | 規劃中 |
