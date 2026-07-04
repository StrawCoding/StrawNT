# StrawWU UX / Design System

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 對齊 | `/mnt/data/Data/檔案/專案資料/StrawWU/strawwu-colors.md` |

## 1. 視覺語言

| Token | 值 | 用途 |
|-------|-----|------|
| --sw-teal | #14B8A6 | 主色、進度、focus |
| --sw-teal-dark | #0D9488 | hover |
| --sw-bg | #0A0E14 | 深色背景 |
| --sw-surface | #121820 | 卡片 |
| --sw-text | #F4F6F9 | 主文字 |
| --sw-muted | #A9B6C3 | 次要 |
| --sw-warn | #F59E0B | 警告 |
| --sw-error | #F87171 | 錯誤 |

**禁止：** 玻璃擬態、光暈、emoji 作為 UI 圖示

## 2. 字體

- UI：Noto Sans TC / Inter
- Mono：SF Mono / JetBrains Mono
- 最小可讀：14px body

## 3. Icon

- 來源：StrawWU Logo 套件（圓角 icon 22%）
- 尺寸：16/24/32/48 grid

## 4. Spacing

- 4px 基數：4, 8, 12, 16, 24, 32, 48

## 5. Dark / Light

- v0.5 預設 **Dark**（StrawWU-Dark GTK）
- Light：v0.6 Hub 切換

## 6. Wireframes（文字）

### firstboot
[Logo] → 歡迎 → 語言 → 隱私同意 → Flathub → 桌面導覽 → 完成

### Hub 分頁
概覽 | 桌面 | 應用程式 | Flathub | Windows | 更新 | 回報問題 | 關於

## 7. 狀態樣式

| 狀態 | 視覺 |
|------|------|
| loading | Teal 進度條（非 spinner 光暈） |
| empty | 插圖 + 單行說明 + CTA |
| error | 左框 error 色 + SWU-xxx 碼 |
| success | ok 色 pill |

## 8. 無障礙

- WCAG AA 對比
- 全鍵盤 firstboot / Hub
- atk labels 於 GTK4
- 螢幕閱讀器：狀態朗讀含錯誤碼

## 9. 本地化

- v0.5：繁中 + 英文
- 字串：`/usr/share/strawwu/locale/`
- 禁止硬編碼 UI 字串

## 10. Phase UX0–UX3（合 D0）

| Phase | 工作 |
|-------|------|
| UX0 | tokens.css + GTK theme 對齊 |
| UX1 | firstboot wireframe 實作審核 |
| UX2 | Hub 6 分頁 mock → 實作 |
| UX3 | a11y audit |
