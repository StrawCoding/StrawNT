# StrawWU Portable

跨發行版可攜 **Windows 應用執行核心**（prefix／AppImage／CLI）。  
獨立倉庫：與 [StrawWU ISO／桌面發行版](https://github.com/StrawCoding/StrawWU-v2) 分開。

**授權：MIT（開源）** · 預設分支唯一 `main`

## 一鍵安裝（Linux x86_64）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
```

安裝時會：
1. 下載最新 Release 產物
2. 啟用 **雙擊 .exe / .msi → 安裝／啟動**（`execution_backend=native`）

```bash
strawwu --version
strawwu status          # 應顯示 backend=native
strawwu integrate       # 換桌面後再開一次
```

### 點擊就能安裝與啟動

1. 檔案管理員 **雙擊** `.exe` / `.msi`
2. StrawWU 經自研 **strawwu-nt**（`execution_backend=native`）處理安裝／啟動
3. 寫入應用選單捷徑，之後可一鍵再開

```bash
strawwu open setup.exe          # 安裝程式 → native + 捷徑
strawwu open game.exe           # 一般程式 → native + 捷徑
strawwu install setup.exe       # 同上（安裝模式）
strawwu run app.exe             # 預設 backend=native
```

預設裝到 `~/.local/share/strawwu-core`。

## 誠實邊界

- 預設執行路徑為自研 **strawwu-nt**／`execution_backend=native`（**不**使用 Wine／Proton）
- **不保證**所有 Windows 軟體都可跑（反作弊／核心驅動／部分遊戲可能失敗）
- Flatpak 對 PE／session 為 **PARTIAL**
- **不是** StrawWU ISO／桌面安裝器

已煙測容器：Ubuntu 24.04、Fedora 41、Arch Linux。

## 手動下載

到 [Releases](https://github.com/StrawCoding/StrawWU-portable/releases) 下載 `*.portable.tar.gz` / AppImage / `SHA256SUMS`。

## 從原始碼建置

```bash
git clone https://github.com/StrawCoding/StrawWU-portable.git
cd StrawWU-portable
make portable-prefix
make portable-appimage
make test-portable-prefix
```

需要 Rust（`cargo`）。詳見 `docs/plans/portable-core/USER-GUIDE.md`。

## 版本

`a.b.c.d`（`d`=preview，`0`=正式）。目前見根目錄 `VERSION`。

## 授權

[MIT](./LICENSE) © 2026 StrawCoding
