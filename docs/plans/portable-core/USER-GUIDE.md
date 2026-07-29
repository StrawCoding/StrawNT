# StrawWU Portable Core — 使用者指南

Track **A+3**：在通用 Linux（deb／rpm／Arch 等）以最少系統依賴執行
StrawWU **Win 相容核心**（runtime／nt／launcher／graphics·audio／Hub／CLI）。

> **誠實邊界**：本指南**不宣稱**完整 Windows 應用相容；不使用 Wine／Proton 當底層；
> 不引入 `WinBox`／`winbox` 命名。Flatpak 對 PE／SubsystemSession 為 **PARTIAL**。

## 選擇哪一種包裝

| 形態 | 適合 | 指令入口 |
|------|------|----------|
| 自含 prefix | 開發／固定安裝目錄 | `make portable-prefix` |
| AppImage／portable.tar.gz | 單目錄可攜、跨發行版優先 | `make portable-appimage` |
| Flatpak | 發行版商店／sandbox 試用（誠實 PARTIAL） | `make portable-flatpak` |

ISO／Live USB／桌面策展屬另一軌道，**不在此範圍**。

## 一鍵安裝（終端使用者）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
strawwu --version
strawwu status
```

自訂：`bash -s -- --prefix "$HOME/.local/strawwu"` 或 `--version 0.7.1.15`。

## 快速開始（prefix／開發建置）

```bash
make portable-prefix
export STRAWWU_PREFIX="$PWD/components/packaging/portable/prefix"
"$STRAWWU_PREFIX/bin/strawwu" --version
"$STRAWWU_PREFIX/bin/strawwu" status
```

不需系統 `strawwu-*` deb。可選 Hub：`STRAWWU_PORTABLE_WITH_HUB=1 make portable-prefix`。

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

預設矩陣：Ubuntu 24.04、Fedora 41、Arch（容器；非實機 ISO）。

## 產物與校驗

- 索引：`docs/plans/portable-core/artifacts.json`
- 校驗：`tests/portable/output/SHA256SUMS`
- 元件對照：`docs/plans/portable-core/inventory.json`

## 支援與回報

問題請附：`VERSION`、包裝形態、相關 `tests/portable/output/*.json`。
Hub「關於」→ 回報問題（若已安裝完整 StrawWU）；Portable-only 環境可開 GitHub issue。
