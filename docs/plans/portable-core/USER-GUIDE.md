# StrawWU Portable Core — 使用者指南

Track **A+3**：在通用 Linux（deb／rpm／Arch 等）以最少系統依賴執行
StrawWU **Win 相容核心**（runtime／nt／launcher／graphics·audio／Hub／CLI）。

> **誠實邊界**：預設以自研 **strawwu-nt**（`execution_backend=native`）處理 `.exe`／`.msi`。
> **不**使用 Wine／Proton。不保證所有 Windows 軟體都可跑；反作弊／核心驅動可能失敗。
> Flatpak 對 PE／SubsystemSession 為 **PARTIAL**。不是 ISO／桌面發行版。
> pe1 起：最小 console PE fixture 經 native CPU 迴圈可產生可觀測副作用（`mode=real`）；更大範圍相容仍依 pe2+ 推進。
> pe2：kernel32 檔案／行程 + msvcrt CRT 路徑足以跑小型 console `.exe`（非 stub-only）；證據 `tests/portable/output/pe-console.json`。
> pe3：user32/gdi 最小視窗＋訊息迴圈；真實 GUI PE 可顯示／關閉；證據含截圖與 compositor 觀測（`tests/portable/output/pe-gui.json`）。
> pe4：EXE/MSI native 解包安裝＋app-registry＋捷徑；`open` 同路徑（`tests/portable/output/pe-installer.json`）。
> pe5：MIME/`integrate`／選單捷徑只走 native；雙擊 `open` 可安裝／啟動；選單可再開（`tests/portable/output/pe-desktop-click.json`）；`install.sh` 無 Wine。
> pe6：公開小型 Win 程式（7za／BusyBox）native 啟動證據為 **PARTIAL**（載入＋CPU 執行有；完整 CLI 副作用仍待加深；`tests/portable/output/pe-golden.json`）。
> pe7：文件／Release 產物／跨發行版 smoke／HTML closeout（`tests/portable/output/pe-closeout.json`）。
> gx0：DXGI/D3D11→Vulkan + wgl→GL present／triangle 證據（`gx-graphics.json`）。
> gx1：WASAPI→PipeWire/ALSA + 基本輸入路徑（`gx-audio-input.json`）。
> gx2：≥2 輕量 2D/3D 標竿 native 啟動（`gx-light-games.json`；apps 可含誠實 PARTIAL）。
> gx3：Steam／Epic／三角洲級 **啟動器僅驗啟動**（`gx-launchers.json` = **PARTIAL**；不保證遊戲本體暢玩）。
> gx4：EAC/BE/Vanguard 探測矩陣（`gx-anticheat.json` = **PARTIAL**；grade 含 F；**禁止**宣稱排位／官方 AC 簽章通過）。
> gx5：Game Compat 文件誠實邊界／Release／跨發行版 smoke／HTML closeout（`gx-closeout.json`）。

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

自訂：`bash -s -- --prefix "$HOME/.local/strawwu"` 或 `--version` 對應 GitHub Release tag（見根目錄 `VERSION`）。

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

## Native PE 驗收證據（pe0–pe7）

| Stage | JSON |
|-------|------|
| pe0 撤回 Wine | `tests/portable/output/pe0-remove-wine.json` |
| pe1 真實 CPU | `tests/portable/output/pe-real-exec.json` |
| pe2 Console MVP | `tests/portable/output/pe-console.json` |
| pe3 GUI MVP | `tests/portable/output/pe-gui.json` |
| pe4 Installer | `tests/portable/output/pe-installer.json` |
| pe5 桌面點擊 | `tests/portable/output/pe-desktop-click.json` |
| pe6 黃金煙測 | `tests/portable/output/pe-golden.json`（允許誠實 PARTIAL） |
| pe7 Closeout | `tests/portable/output/pe-closeout.json` |

```bash
make test-portable-pe-closeout
jq .status tests/portable/output/pe-closeout.json
```

## Game Compat 驗收證據（gx0–gx5）

| Stage | JSON |
|-------|------|
| gx0 圖形 VK/GL | `tests/portable/output/gx-graphics.json` |
| gx1 音訊／輸入 | `tests/portable/output/gx-audio-input.json` |
| gx2 輕量 2D/3D | `tests/portable/output/gx-light-games.json` |
| gx3 啟動器煙測 | `tests/portable/output/gx-launchers.json`（誠實 **PARTIAL**） |
| gx4 反作弊矩陣 | `tests/portable/output/gx-anticheat.json`（誠實 **PARTIAL**；非排位可用） |
| gx5 Closeout | `tests/portable/output/gx-closeout.json` |

```bash
make test-portable-gx-closeout
jq .status tests/portable/output/gx-closeout.json
```

## 產物與校驗

- 索引：`docs/plans/portable-core/artifacts.json`
- 校驗：`tests/portable/output/SHA256SUMS`
- 元件對照：`docs/plans/portable-core/inventory.json`
- Closeout HTML：`docs/plans/portable-core/html/pe-closeout-report.html`、`html/gx-closeout-report.html`

## 支援與回報

問題請附：`VERSION`、包裝形態、相關 `tests/portable/output/*.json`。
Hub「關於」→ 回報問題（若已安裝完整 StrawWU）；Portable-only 環境可開 GitHub issue。
