# StrawWU 使用者文件

| 版本 | 對齊 `VERSION` |
|------|----------------|
| 語系 | 繁體中文（部分章節含英文對照） |
| 範圍 | v0.5 預發布 — 安裝、Live、首次設定、基礎救援、完整手冊 |

本目錄為 **DOC0 資訊架構** 與 **DOC1 安裝／救援指南** 的正式來源。工程計畫與 PRD 見 `docs/plans/`。

## 指南索引

| 文件 | 說明 | HTML（hermes-deliver） |
|------|------|------------------------|
| [install-guide.md](install-guide.md) | Live USB、試用、安裝、首次設定（firstboot） | [html/install-guide.html](html/install-guide.html) |
| [rescue-guide.md](rescue-guide.md) | Live 救援、狀態修復、安裝失敗排除 | [html/rescue-guide.html](html/rescue-guide.html) |
| [portable-guide.md](portable-guide.md) | Portable Core（跨發行版可攜核心，非 ISO） | 見 `docs/plans/portable-core/` |

## 完整手冊（W8-DOC）

| 文件 | 說明 |
|------|------|
| [handbook/README.md](handbook/README.md) | 使用者＋管理員手冊索引（DOC2 wincompat、DOC3 upgrade/rescue） |
| [handbook/user-handbook.md](handbook/user-handbook.md) | 日常使用：Hub、Apps、Flathub、更新 |
| [handbook/admin-handbook.md](handbook/admin-handbook.md) | 管理維運：initd、APT、發佈、initramfs |
| [handbook/wincompat-guide.md](handbook/wincompat-guide.md) | Windows 相容等級 A/B/C/F |
| [handbook/upgrade-rescue-guide.md](handbook/upgrade-rescue-guide.md) | 升級失敗與 rollback 誠實邊界 |

## 快速流程

```
下載 ISO → 寫入 USB → Live 試用 → 安裝 StrawWU → 重新開機 → 首次設定精靈 → 日常使用
```

若已安裝系統無法開機或設定損毀，請改閱 [rescue-guide.md](rescue-guide.md)。

## 取得 ISO

正式驗收使用 **release-iso** 產物：

- 檔名：`StrawWU-<版本>-amd64.iso`（例：`StrawWU-0.4.1.39-amd64.iso`）
- 建置：見 `docs/iso-modes.md`（開發者）或官方發佈頁（TBD）

## 支援與回報

| 管道 | v0.5 狀態 |
|------|-----------|
| Hub「關於」→ 回報問題 | 已內建 `strawwu-bug-report-gtk` |
| 官方論壇 / Matrix / Discord | **TBD**（v1.0 路線，不阻擋本階段） |
| 支援網址 | **TBD** — `https://strawwu.local/support`（佔位） |

## 文件階段狀態

| Phase | 主題 | 狀態 |
|-------|------|------|
| DOC0 | 資訊架構 | 完成 |
| DOC1 | 安裝／救援指南 | 完成 |
| DOC2 | Windows 相容分級 | 完成（[handbook/wincompat-guide.md](handbook/wincompat-guide.md)） |
| DOC3 | 升級 rollback／UPG rescue | 完成（[handbook/upgrade-rescue-guide.md](handbook/upgrade-rescue-guide.md)） |
| Handbook | 使用者＋管理員手冊 | 完成（[handbook/](handbook/)） |
