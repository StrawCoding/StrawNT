# StrawWU Portable Core 指南

本頁說明如何在**非 StrawWU ISO** 的通用 Linux 上，使用 Portable Core（A+3）
執行 Win 相容核心（CLI／runtime）。完整工程細節見
[docs/plans/portable-core/USER-GUIDE.md](../plans/portable-core/USER-GUIDE.md)。

## 誠實邊界

- 預設執行路徑為自研 **strawwu-nt**／`execution_backend=native`
- **不宣稱**完整 Windows 應用相容／反作弊排位可用／3A 全開
- **不使用** Wine／Proton 當底層
- **不使用** `WinBox`／`winbox` 命名
- 公開小工具黃金煙測可為 **PARTIAL**（見 `pe-golden.json`）
- Game Compat：啟動器僅驗啟動（`gx-launchers.json` PARTIAL）；反作弊為探測矩陣（`gx-anticheat.json` PARTIAL）
- Flatpak 對 PE／SubsystemSession：**PARTIAL**（需 host filesystem）
- **不取代** Live USB／安裝版 ISO 軌道

## 一鍵安裝（推薦）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
strawwu --version
strawwu status
```

腳本從 GitHub Releases 下載 `portable.tar.gz`，裝到
`~/.local/share/strawwu-core`，把 `strawwu` 連到 `~/.local/bin`，
並執行 `strawwu integrate` 啟用 **雙擊 .exe/.msi → 安裝與啟動**。

```bash
strawwu integrate              # 重裝／換桌面後再開
strawwu open setup.exe         # 或直接雙擊檔案
```

安裝／開啟後會在 `~/.local/share/applications/` 寫入捷徑，可從應用選單再開。

## 三種形態（手動／建置）

1. **自含 prefix** — `make portable-prefix`，執行 `$STRAWWU_PREFIX/bin/strawwu`
2. **AppImage／portable.tar.gz** — `make portable-appimage`（跨發行版優先）
3. **Flatpak** — `make portable-flatpak`（見 sandbox 說明）

校驗檔：`tests/portable/output/SHA256SUMS`  
產物索引：`docs/plans/portable-core/artifacts.json`

## 與安裝指南的關係

若你使用 **StrawWU ISO／Live USB**，請改閱 [install-guide.md](install-guide.md)。
Portable Core 是給其他發行版／可攜部署的並行軌道。
