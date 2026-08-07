# StrawNT — 使用者指南

在通用 Linux（deb／rpm／Arch 等）以最少系統依賴執行
**StrawNT**（Wine／Proton-GE 執行核心 + Electron Hub／CLI／prefix）。

> **誠實邊界**：預設以 **Wine／Proton-GE**（`execution_backend=wine`）處理 `.exe`／`.msi`。
> 狀態須標示 **powered by Wine**。不保證所有 Windows 軟體都可跑；反作弊／核心驅動可能失敗。
> Flatpak 對 PE／SubsystemSession 為 **PARTIAL**。不是 ISO／桌面發行版。
> StrawNT 為獨立產品，與任何 OS ISO／桌面／kernel 發行軌道無關。
>
> **契約翻轉（2026-08-07／NTW0）：** 已**廢止**舊「禁 Wine／不使用 Wine」產品硬契約（歷史 archive／legacy 證據除外）。見 `docs/decisions/2026-08-07-wine-pivot.md`。

## 選擇哪一種包裝

| 形態 | 適合 | 指令入口 |
|------|------|----------|
| 自含 prefix | 開發／固定安裝目錄 | `make portable-prefix` |
| AppImage／portable.tar.gz | 單目錄可攜、跨發行版優先 | `make portable-appimage` |
| Flatpak | 發行版商店／sandbox 試用（誠實 PARTIAL） | `make portable-flatpak` |

ISO／Live USB／桌面策展**不在本產品範圍**。

## 一鍵安裝（終端使用者）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawNT/main/install.sh | bash
strawnt --version
strawnt status
```

自訂：`bash -s -- --prefix "$HOME/.local/strawnt"` 或 `--version` 對應 GitHub Release tag（見根目錄 `VERSION`）。

對外 CLI 為 **`strawnt`**。舊命令名 `strawwu` 若仍存在，僅為相容別名，文件與主路徑以 `strawnt` 為準。

## 快速開始（prefix／開發建置）

```bash
make portable-prefix
export STRAWNT_PREFIX="$PWD/components/packaging/portable/prefix"
"$STRAWNT_PREFIX/bin/strawnt" --version
"$STRAWNT_PREFIX/bin/strawnt" status
```

不需系統 deb。可選 Hub：`STRAWNT_PORTABLE_WITH_HUB=1 make portable-prefix`（相容舊 env `STRAWWU_PORTABLE_WITH_HUB`）。

## 快速開始（AppImage／portable bundle）

```bash
make portable-appimage
# 產物在 components/packaging/portable/appimage/dist/
# 驗證：
make test-portable-appimage
jq .status tests/portable/output/smoke-appimage.json
sha256sum -c tests/portable/output/SHA256SUMS
```

乾淨容器煙測使用 `portable.tar.gz`（等同 AppDir 內容打包），避免 FUSE 依賴。

## Flatpak（PARTIAL）

```bash
make portable-flatpak
make test-portable-flatpak
jq .status tests/portable/output/smoke-flatpak.json   # 預期 PARTIAL
```

權限說明見 `components/packaging/portable/flatpak/SANDBOX-NOTES.md`。
PE／SubsystemSession 需要 host filesystem；**不可**當成完整 sandbox 相容。

## 跨發行版煙測

```bash
make test-portable-matrix
jq .status tests/portable/output/matrix.json
```

## 環境變數

| 變數 | 說明 |
|------|------|
| `STRAWNT_PREFIX` | 安裝／prefix 根目錄（主路徑） |
| `STRAWNT_BACKEND` | 預設 `wine`（產品路徑） |
| `STRAWNT_LEGACY_NATIVE` | 設為 `1` 啟用舊 native PE 研究路徑（**unsupported**） |
| `STRAWNT_APP_REGISTRY` | 本機 app-registry JSON |
| `STRAWNT_BIN` | desktop Exec 使用的 CLI 路徑 |

舊 `STRAWWU_*` 變數仍可讀作相容層，新部署請改用 `STRAWNT_*`。

## 優玩軌道（nt0–nt6）摘要 — 歷史／legacy

下列為 Wine pivot **之前**的 native 預設軌道證據（保留；非現行產品契約）：

| 階段 | 證據 | 誠實狀態 |
|------|------|----------|
| nt0 更名 | `tests/strawnt/output/nt0-rebrand.json` | 歷史 PASS（native-era） |
| nt1 圖形 | `nt1-graphics.json` | 歷史 PASS（native-era） |
| nt2 輕量遊戲 | `nt2-light-games.json` | 歷史 PASS（native-era） |
| nt3 啟動器 | `nt3-launchers.json` | 歷史 PARTIAL |
| nt4 反作弊 | `nt4-anticheat.json` | 歷史 PARTIAL（禁排位宣稱仍有效） |
| nt5 closeout | `nt5-closeout.json` | 歷史 closeout |
| nt6 openable | `nt6-openable.json` | 歷史 PASS |

Wine pivot 契約證據：`tests/strawnt/output/ntw0-contract.json`。盤點：`tests/archive/native/README.md`。

## 誠實非目標

- 不宣稱完整 Windows 應用相容／反作弊排位通過／官方 AC 簽章通過／3A 全開
- 啟動器僅驗啟動範圍內行為；**不**保證遊戲本體完整暢玩
- 反作弊為探測矩陣（誠實 PARTIAL）；**禁止**排位／官方通過宣稱
- 不以自研 PE **偽裝**取代 Wine；旗艦為 **powered by Wine**／proton-ge
- 不使用 `WinBox`／`winbox` 命名混淆 StrawWinBox
- 不提供／不依賴任何 OS ISO／桌面／kernel 產物
