# StrawWU 完整手冊

| 版本 | 對齊 `VERSION` |
|------|----------------|
| 語系 | 繁體中文（部分章節含英文對照） |
| 範圍 | v1.0 — 日常使用、管理維運、Windows 相容、升級救援、系統更新 |

本目錄為 **W8-DOC handbook** 正式來源，整合 DOC2（Windows 相容分級）與 DOC3（升級／rollback 誠實說明）。安裝與基礎救援見上層 `docs/user/`。

## 手冊索引

| 文件 | 對象 | 說明 | HTML |
|------|------|------|------|
| [user-handbook.md](user-handbook.md) | 一般使用者 | 桌面、Hub、應用程式、Flathub、更新、問題回報 | [html/user-handbook.html](html/user-handbook.html) |
| [admin-handbook.md](admin-handbook.md) | 系統管理員 | initd、target-setup、meta、APT 倉庫、發佈、initramfs | [html/admin-handbook.html](html/admin-handbook.html) |
| [wincompat-guide.md](wincompat-guide.md) | 使用者／進階 | Windows 應用相容等級 A/B/C/F、Hub 顯示、誠實邊界 | [html/wincompat-guide.html](html/wincompat-guide.html) |
| [upgrade-rescue-guide.md](upgrade-rescue-guide.md) | 使用者／管理員 | 升級失敗處理、rollback 路線圖、UPG 與 Live 救援 | [html/upgrade-rescue-guide.html](html/upgrade-rescue-guide.html) |
| [update-guide.md](update-guide.md) | 一般使用者 | 日常 APT/Hub 更新、更新通道、重大升級、Flatpak、備份 | [html/update-guide.html](html/update-guide.html) |

## 快速導覽

```
新使用者 → install-guide.md → firstboot → user-handbook.md
Windows 遊戲／應用 → wincompat-guide.md → Hub「Windows 相容」
系統更新 → update-guide.md → Hub「軟體源」／「更新通道」
系統異常 → rescue-guide.md（基礎）→ upgrade-rescue-guide.md（升級情境）
管理員維運 → admin-handbook.md
```

## 相關文件

| 文件 | 路徑 |
|------|------|
| 安裝與首次設定 | [../install-guide.md](../install-guide.md) |
| 基礎救援 | [../rescue-guide.md](../rescue-guide.md) |
| 使用者文件總索引 | [../README.md](../README.md) |

## 支援與回報

| 管道 | v0.5 狀態 |
|------|-----------|
| Hub「關於」→ 回報問題 | `strawwu-bug-report-gtk` |
| 官方論壇 / Matrix / Discord | **TBD**（v1.0 路線） |
| 支援網址 | **TBD** — `https://strawwu.local/support`（佔位） |
