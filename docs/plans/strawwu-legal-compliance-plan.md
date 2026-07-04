# StrawWU 法務 / 授權 / 商標合規計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 1. 原則

技術 rebrand 不足；須可稽核的合規清單與使用者可見法律文件。

## 2. Ubuntu / Canonical 商標移除清單

| 表面 | 檢查點 | 目標 |
|------|--------|------|
| os-release | PRETTY_NAME, NAME | StrawWU only |
| GRUB | 選單標題 | StrawWU |
| Plymouth | 開機文字 | StrawWU |
| Calamares | show.qml, branding | 無 Ubuntu logo |
| About dialog | Hub / Settings | StrawWU + 第三方致謝 |
| .desktop | Name/Comment | 無 "Ubuntu" |
| MOTD / issue | /etc | StrawWU 或移除 |
| 文件 / 說明 | yelp → strawwu-docs | 無 ubuntu-docs 品牌 |

**內部保留（不暴露 UI）：** `ID=ubuntu`、`username=ubuntu`、Ubuntu apt keyring（過渡期）

## 3. deb 授權盤點

- 產出：`docs/plans/license-inventory.csv`（package, license, source-required）
- GPL/LGPL：source offer 在 `/usr/share/doc/*/copyright` + 官網 source 連結
- MIT/Apache：保留 NOTICE
- 禁止宣稱 Canonical 背書

## 4. Proprietary 邊界

| 可開源 | 可專有 |
|--------|--------|
| strawwu-shell, hub, branding | 未來商業插件 |
| compat stubs | 第三方遊戲 binary |
| 建置腳本 | 使用者資料 |

## 5. Windows / Microsoft 名稱

- UI：「Windows 相容模式」非「Windows」
- 禁止暗示 Microsoft 認證
- 商店 app 圖示遵循各平台商標指引

## 6. Flathub 第三方責任

- Hub 顯示：「應用程式由 Flathub 第三方維護，非 StrawWU 官方」
- 安裝前 Flatpak permission 摘要

## 7. 使用者法律文件草案

| 文件 | 位置 |
|------|------|
| Privacy Policy | `/usr/share/strawwu/legal/privacy.html` |
| EULA（草） | firstboot 步驟 3 連結 |
| Third-party notices | Hub → 關於 |

## 8. Phase LEG0–LEG4

| Phase | 工作 |
|-------|------|
| LEG0 | 商標掃描腳本 `scan-ubuntu-trademarks.sh` |
| LEG1 | license-inventory.csv 自動產生 |
| LEG2 | privacy + EULA 草案 HTML |
| LEG3 | Calamares/GRUB/Plymouth 合規審計 |
| LEG4 | release 前合規 gate（CI） |
