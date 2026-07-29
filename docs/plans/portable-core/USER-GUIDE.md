# StrawNT — 使用者指南

在通用 Linux（deb／rpm／Arch 等）以最少系統依賴執行
**StrawNT** native PE／NT ABI 執行核心（runtime／nt／launcher／graphics·audio／Hub／CLI）。

> **誠實邊界**：預設以自研 **native PE**（`execution_backend=native`）處理 `.exe`／`.msi`。
> **不**使用 Wine／Proton。不保證所有 Windows 軟體都可跑；反作弊／核心驅動可能失敗。
> Flatpak 對 PE／SubsystemSession 為 **PARTIAL**。不是 ISO／桌面發行版。
> StrawNT 為獨立產品，與任何 OS ISO／桌面／kernel 發行軌道無關。

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
| `STRAWNT_BACKEND` | 預設 `native` |
| `STRAWNT_APP_REGISTRY` | 本機 app-registry JSON |
| `STRAWNT_BIN` | desktop Exec 使用的 CLI 路徑 |

舊 `STRAWWU_*` 變數仍可讀作相容層，新部署請改用 `STRAWNT_*`。

## 誠實非目標

- 不宣稱完整 Windows 應用相容／反作弊排位通過／3A 全開
- 不使用 Wine／Proton 當底層
- 不使用 `WinBox`／`winbox` 命名
- 不提供／不依賴任何 OS ISO／桌面／kernel 產物
