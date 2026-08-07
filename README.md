# StrawNT

跨發行版可攜 **Wine／Proton-GE** Windows 應用執行平台（prefix／AppImage／CLI／Electron Hub）。  
獨立產品倉庫：[StrawCoding/StrawNT](https://github.com/StrawCoding/StrawNT)。

**授權：MIT（開源殼）＋ Wine LGPL 基板** · 預設分支唯一 `main`  
**powered by Wine** · 預設 `execution_backend=wine` · 引擎 `proton-ge`（vendored／git-lfs）

> **2026-08-07 Wine pivot：** 已**廢止**舊「禁 Wine／Proton」產品硬契約（歷史 archive 證據另見 `tests/archive/native/`）。決策：`docs/decisions/2026-08-07-wine-pivot.md`。

## 一鍵安裝（Linux x86_64）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawNT/main/install.sh | bash
```

安裝時會：
1. 下載最新 Release 產物（或 `install.sh --local` 本機產物）
2. 把 `strawnt` 掛到 `~/.local/bin`（並寫入 `~/.config/strawnt/env.sh`）
3. 清除舊 StrawWU／壞掉的暫存路徑 MIME handler
4. 寫入應用選單入口（`strawnt.desktop` → `status`）與雙擊 handler（`strawnt-open.desktop`）

```bash
strawnt --version
strawnt status          # 應顯示 backend=wine · powered by Wine
strawnt integrate       # 換桌面／清 stale handler 後再開一次
```

### 點擊就能安裝與啟動

1. 應用選單開 **StrawNT**（執行 `status`；不需檔案參數）
2. 檔案管理員 **雙擊** `.exe` / `.msi`（MIME → `strawnt open`）
3. StrawNT 經 **Wine／Proton-GE**（`execution_backend=wine`）處理安裝／啟動
4. 寫入應用選單捷徑，之後可一鍵再開

```bash
strawnt open setup.exe          # 安裝程式 → wine/GE + 捷徑
strawnt open game.exe           # 一般程式 → wine/GE + 捷徑
strawnt install setup.exe       # 同上（安裝模式）
strawnt run app.exe             # 預設 backend=wine
```

預設裝到 `~/.local/share/strawnt`。對外 CLI 為 `strawnt`（舊 `strawwu` 僅相容別名，非主路徑）。

引擎 vendor（完整 GE 樹）見後續 NTW1；大檔以 **git-lfs** 配送。過渡期若需舊 native PE 研究路徑：`STRAWNT_LEGACY_NATIVE=1`（**unsupported**）。

## 誠實邊界

- 預設執行路徑為 **Wine／Proton-GE**／`execution_backend=wine`（**powered by Wine**）
- **不保證**所有 Windows 軟體都可跑（反作弊／核心驅動／部分遊戲可能失敗）
- 相容狀態僅允許 PASS／PARTIAL／FAIL／UNKNOWN；**禁止**宣稱排位／官方 AC 簽章通過或完整 Windows／3A 全開
- Flatpak 對 PE／session 為 **PARTIAL**
- **不是**任何作業系統 ISO／桌面發行版；與其他 StrawCoding OS／ISO 產品無執行依賴
- 法律：`docs/legal/WINE-LGPL.md`、`THIRD_PARTY_NOTICES`

已煙測容器：Ubuntu 24.04、Fedora 41、Arch Linux（包裝軌道；引擎完整度依階段）。

## 手動下載

到 [Releases](https://github.com/StrawCoding/StrawNT/releases) 下載 `*.portable.tar.gz` / AppImage / `SHA256SUMS`。

## 從原始碼建置

```bash
git clone https://github.com/StrawCoding/StrawNT.git
cd StrawNT
make portable-prefix
make portable-appimage
make test-portable-prefix
```

需要 Rust（`cargo`）。詳見 `docs/plans/portable-core/USER-GUIDE.md`。

## 版本

`a.b.c.d`（`d`=preview，`0`=正式）。目前見根目錄 `VERSION`。

## 授權

[MIT](./LICENSE) © 2026 StrawCoding（自有殼）· Wine／GE 見 [docs/legal/WINE-LGPL.md](./docs/legal/WINE-LGPL.md)
