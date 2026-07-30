# StrawNT

跨發行版可攜 **native PE／NT ABI 執行核心**（prefix／AppImage／CLI）。  
獨立產品倉庫：[StrawCoding/StrawNT](https://github.com/StrawCoding/StrawNT)。

**授權：MIT（開源）** · 預設分支唯一 `main`

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
strawnt status          # 應顯示 backend=native
strawnt integrate       # 換桌面／清 stale handler 後再開一次
```

### 點擊就能安裝與啟動

1. 應用選單開 **StrawNT**（執行 `status`；不需檔案參數）
2. 檔案管理員 **雙擊** `.exe` / `.msi`（MIME → `strawnt open`）
3. StrawNT 經自研 **native PE**（`execution_backend=native`）處理安裝／啟動
4. 寫入應用選單捷徑，之後可一鍵再開

```bash
strawnt open setup.exe          # 安裝程式 → native + 捷徑
strawnt open game.exe           # 一般程式 → native + 捷徑
strawnt install setup.exe       # 同上（安裝模式）
strawnt run app.exe             # 預設 backend=native
```

預設裝到 `~/.local/share/strawnt`。對外 CLI 為 `strawnt`（舊 `strawwu` 僅相容別名，非主路徑）。

## 誠實邊界

- 預設執行路徑為自研 **native PE**／`execution_backend=native`（**不**使用 Wine／Proton）
- **不保證**所有 Windows 軟體都可跑（反作弊／核心驅動／部分遊戲可能失敗）
- Game Compat：圖形／音訊橋接可證；輕量遊戲可啟動；商店／啟動器**僅驗啟動**；反作弊為探測矩陣（誠實 PARTIAL）— **禁止**宣稱排位／官方 AC 簽章通過或 3A 全開
- Flatpak 對 PE／session 為 **PARTIAL**
- **不是**任何作業系統 ISO／桌面發行版；與其他 StrawCoding 產品無執行依賴

已煙測容器：Ubuntu 24.04、Fedora 41、Arch Linux。

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

[MIT](./LICENSE) © 2026 StrawCoding
