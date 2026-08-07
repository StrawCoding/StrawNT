# StrawNT 使用者指南

本頁說明如何在通用 Linux 上使用 **StrawNT**（Wine／Proton-GE 執行平台）。
完整工程細節見 [docs/plans/portable-core/USER-GUIDE.md](../plans/portable-core/USER-GUIDE.md)。

## 誠實邊界

- 預設執行路徑為 **Wine／Proton-GE**／`execution_backend=wine`（**powered by Wine**）
- **不宣稱**完整 Windows 應用相容／反作弊排位可用／3A 全開
- 相容矩陣僅允許 PASS／PARTIAL／FAIL／UNKNOWN；禁排位／官方通過宣稱
- 舊「不使用 Wine／Proton」產品硬契約已於 2026-08-07 **廢止**（歷史 archive 除外）
- **不使用** `WinBox`／`winbox` 命名混淆
- Flatpak 對 PE／SubsystemSession：**PARTIAL**（需 host filesystem）
- StrawNT **不是** OS／ISO／桌面發行版；與其他產品無執行依賴
- 法律：`docs/legal/WINE-LGPL.md` · ADR：`docs/decisions/2026-08-07-wine-pivot.md`

## 一鍵安裝（推薦）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawNT/main/install.sh | bash
strawnt --version
strawnt status
```

腳本從 GitHub Releases 下載 `portable.tar.gz`，裝到
`~/.local/share/strawnt`，把 `strawnt` 連到 `~/.local/bin`，
清除舊 StrawWU／暫存路徑 handler，並執行 `strawnt integrate`：
應用選單有可啟動的 **StrawNT**；雙擊 `.exe`/`.msi` → 安裝與啟動。

```bash
strawnt integrate              # 重裝／換桌面後再開（會清 stale handler）
strawnt open setup.exe         # 或直接雙擊檔案
```

安裝／開啟後會在 `~/.local/share/applications/` 寫入捷徑，可從應用選單再開。

## 三種形態（手動／建置）

1. **自含 prefix** — `make portable-prefix`，執行 `$STRAWNT_PREFIX/bin/strawnt`
2. **AppImage／portable.tar.gz** — `make portable-appimage`
3. **Flatpak** — `make portable-flatpak`（誠實 PARTIAL）
