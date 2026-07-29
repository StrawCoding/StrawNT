# StrawWU Portable

跨發行版可攜 **Win 相容核心**（prefix／AppImage／CLI）。  
獨立倉庫：與 [StrawWU ISO／桌面發行版](https://github.com/StrawCoding/StrawWU-v2) 分開。

**授權：MIT（開源）** · 預設分支唯一 `main`

## 一鍵安裝（Linux x86_64）

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash
```

安裝後會自動啟用 **點擊安裝／啟動**（`.exe` / `.msi` MIME 關聯）。

```bash
strawwu --version
strawwu status
strawwu integrate   # 若換桌面／重裝後需再開一次
```

### 點擊就能安裝與啟動

1. 檔案管理員裡 **雙擊** 任何 `.exe` / `.msi`
2. StrawWU 會登錄應用、寫入應用選單捷徑，並啟動
3. 之後也可從應用選單一鍵再開

或用指令：

```bash
strawwu open setup.exe          # 安裝程式 → 登錄 + 啟動 + 捷徑
strawwu open game.exe           # 一般程式 → 啟動 + 捷徑
strawwu open --install foo.exe  # 強制當安裝程式
strawwu open --run foo.exe      # 強制只啟動
```

預設裝到 `~/.local/share/strawwu-core`，並把 `strawwu` 連到 `~/.local/bin`。

自訂路徑／指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash -s -- --prefix "$HOME/.local/strawwu"
curl -fsSL https://raw.githubusercontent.com/StrawCoding/StrawWU-portable/main/install.sh | bash -s -- --version 0.7.1.16
```

## 誠實邊界

- **不宣稱**完整 Windows 應用相容
- **不使用** Wine／Proton 當底層
- Flatpak 對 PE／session 為 **PARTIAL**（常需 host filesystem）
- **不是** StrawWU ISO／桌面安裝器
- 點擊開啟走自有 PE runtime；複雜安裝精靈／反作弊仍可能失敗

已煙測容器：Ubuntu 24.04、Fedora 41、Arch Linux。

## 手動下載

到 [Releases](https://github.com/StrawCoding/StrawWU-portable/releases) 下載：

| 產物 | 用途 |
|------|------|
| `*.portable.tar.gz` | 跨發行版首選（無 FUSE） |
| `*.AppImage` | 單檔執行（可選） |
| `SHA256SUMS` | 校驗 |

```bash
tar -xzf StrawWU-Core-*-x86_64.portable.tar.gz
./StrawWU-Core-*-x86_64.AppDir/AppRun --version
./StrawWU-Core-*-x86_64.AppDir/AppRun integrate
```

## 從原始碼建置

```bash
git clone https://github.com/StrawCoding/StrawWU-portable.git
cd StrawWU-portable
make portable-prefix          # 自含 prefix
make portable-appimage        # AppImage + portable.tar.gz
make test-portable-prefix     # 煙測
make test-portable-appimage
```

需要 Rust（`cargo`）。詳見 `docs/user/portable-guide.md`、`docs/plans/portable-core/USER-GUIDE.md`。

## 版本

`a.b.c.d`（`d`=preview，`0`=正式）。目前見根目錄 `VERSION`。

## 授權

[MIT](./LICENSE) © 2026 StrawCoding
