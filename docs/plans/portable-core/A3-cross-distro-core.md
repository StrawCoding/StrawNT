# StrawWU Portable Core — Track A+3

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本檔為 portable-core 原生決策當時契約。產品預設已改 `execution_backend=wine`／`engine=proton-ge`；下方「禁 Wine／Proton」「native 預設」為**歷史硬契約**，已廢止。現行：`docs/decisions/2026-08-07-wine-pivot.md`。

**決策（使用者 2026-07-29；後經 2026-08-07 soft-reset）：** 方案 A + 平台 3  
- **A（核心範圍）**：Win 相容核心 — `strawwu-runtime` / `strawwu-nt` / `strawwu-launcher` / graphics·audio bridge / Hub / CLI  
- **3（發行形態）**：真正跨發行版 — 優先 **自含 prefix + AppImage**；Flatpak 次之（誠實標 PARTIAL 若需 host 權限）  
- **排除**：桌面策展、Plymouth、Calamares、自訂 kernel、initrd、ISO、drivers meta  
- **執行（歷史）：** 當時預設自研 strawwu-nt（`execution_backend=native`）；**已廢止**「禁 Wine／Proton」產品硬契約。現行預設 wine／proton-ge（powered by Wine）。仍禁宣稱完整 Windows OS／反作弊排位通過；仍禁 `WinBox`／`winbox` 命名、per-app sandbox 預設
- **並行**：不取代 StrawWU ISO／`post-hw-t1-live-usb`；獨立 repo（後更名 StrawNT）
## 目標（最大可能）

在通用 Linux（deb／rpm／Arch 等）上，以**最少系統依賴**安裝並執行 StrawWU Win 相容核心：

1. 自含安裝前綴 `$STRAWWU_PREFIX`（bundled libs + rpath）  
2. 單檔／單目錄產物：**AppImage**（或等價可攜 bundle）  
3. **Flatpak**（若 sandbox 阻擋 PE／SubsystemSession → 記錄限制 + 必要 host portal／filesystem，狀態 PARTIAL）  
4. 跨發行版容器煙測矩陣（至少 Ubuntu LTS、Fedora、Arch）

## 非目標

- 把 StrawWU 變成另一個完整發行版（那是 IND）  
- 在任意 distro 上替換桌面／開機品牌  
- QEMU／實機 Live USB 硬體戰役（仍屬 ISO track）

## 鎖序

| # | stage_id | PASS 條件（摘要） |
|---|----------|-------------------|
| 0 | `pc0-portable-scaffold` | 本計畫 + inventory JSON + packaging 目錄骨架就緒；測試腳本入口存在 |
| 1 | `pc1-self-contained-prefix` | `make portable-prefix`（或等價）產出可執行 prefix；`strawwu --version`／`status` 不依賴系統 strawwu-* deb |
| 2 | `pc2-appimage` | 產出可執行 AppImage（或等價 bundle）；SHA256；乾淨容器煙測 PASS |
| 3 | `pc3-flatpak` | Flatpak manifest + build；煙測結果 JSON（允許誠實 PARTIAL）；文件說明權限需求 |
| 4 | `pc4-cross-distro-smoke` | ≥3 發行版容器矩陣煙測報告 JSON 頂層 `status=PASS`（核心 CLI／runtime 啟動） |
| 5 | `pc5-closeout` | 文件、產物、SHA256、version bump、merge/push `main`、HTML 交付證據（`tests/portable/output/closeout.json`） |

Closeout 產物：`USER-GUIDE.md`、`artifacts.json`、`closeout-report.md` + HTML、`tests/portable/closeout.sh`。

## 驗收權威

- 各 stage 證據 JSON（路徑見 kickoff）頂層 `status`  
- 禁止僅以 `cargo test` 數量宣稱完成  
- 誠實標記：PARTIAL 不可當 PASS

## 工作區

- Repo worktree：`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
- Branch：`portable-core-a3` → closeout 合併 `main`  
- 主 ISO 工作區 `/mnt/data/code/project/StrawCoding/StrawWU` 的 `post-hw-t1-live-usb` **並行、勿搶 ISO build**
