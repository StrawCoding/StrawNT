# StrawNT 使用者指南

本頁說明如何在通用 Linux 上使用 **StrawNT**（native PE／NT ABI 執行核心）。
完整工程細節見 [docs/plans/portable-core/USER-GUIDE.md](../plans/portable-core/USER-GUIDE.md)。

## 誠實邊界

- 預設執行路徑為自研 **native PE**／`execution_backend=native`
- **不宣稱**完整 Windows 應用相容／反作弊排位可用／3A 全開
- 啟動器僅驗啟動（誠實 PARTIAL）；反作弊為探測矩陣（誠實 PARTIAL；禁排位／官方通過宣稱）
- **不使用** Wine／Proton 當底層
- **不使用** `WinBox`／`winbox` 命名
- Flatpak 對 PE／SubsystemSession：**PARTIAL**（需 host filesystem）
- StrawNT **不是** OS／ISO／桌面發行版；與其他產品無執行依賴
- 優玩 closeout 報告：`docs/plans/portable-core/nt5-closeout-report.md`

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
Openable 證據：`tests/strawnt/output/nt6-openable.json`。

## 三種形態（手動／建置）

1. **自含 prefix** — `make portable-prefix`，執行 `$STRAWNT_PREFIX/bin/strawnt`
2. **AppImage／portable.tar.gz** — `make portable-appimage`（跨發行版優先）
3. **Flatpak** — `make portable-flatpak`（見 sandbox 說明）

校驗檔：`tests/portable/output/SHA256SUMS`  
產物索引：`docs/plans/portable-core/artifacts.json`

## 與其他產品的關係

StrawNT 為獨立倉庫與獨立產品敘事。若你需要其他 StrawCoding 產品的 OS／ISO／桌面軌道文件，請到對應倉庫；**本產品不依賴、不打包、不宣稱屬於那些軌道**。
