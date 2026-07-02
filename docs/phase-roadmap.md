# StrawWU Phase 路線圖（v3.0-cleanroom）

| 版本 | 0.3.0-cleanroom |
|------|-----------------|
| 日期 | 2026-07-02 |

## Phase 0 — 骨架與規範 ✅

| # | 驗收標準 | 驗證 |
|---|----------|------|
| 0.1 | 新 repo 骨架、docs、Makefile | 檔案存在 |
| 0.2 | `make preflight` exit 0 | CI |
| 0.3 | 禁止 legacy crate 複製檢查 | preflight |

## Phase 1 — Ubuntu Clone 管線

| # | 驗收標準 |
|---|----------|
| 1.1 | `clone-ubuntu-base.sh` 成功提取 noble desktop rootfs |
| 1.2 | rootfs 內含 `calamares-settings-ubuntu-common` |
| 1.3 | `build-iso.sh` xorriso 產出可開機 ISO |
| 1.4 | QEMU `boot-test-iso` serial marker `STRAWWU_BOOT_OK` |

## Phase 2 — 自訂 Kernel

| # | 驗收標準 |
|---|----------|
| 2.1 | `kernel/` 產出 `linux-image-strawwu` .deb |
| 2.2 | `swap-kernel.sh` 在 chroot 成功替換且可開機 |
| 2.3 | `uname -r` 顯示 strawwu kernel version |

## Phase 3 — Calamares 安裝 E2E

| # | 驗收標準 |
|---|----------|
| 3.1 | preflight 靜態檢查 ALL PASS |
| 3.2 | QEMU 安裝到 virtio 空白碟成功 |
| 3.3 | 安裝後 BIOS/UEFI 雙韌體開機 |

## Phase 4 — 元件基礎（Greenfield）

全新 specs → bridge → runtime → launcher，禁止複製 legacy。

## Phase 5 — 桌面與控制中心

全新 strawwu-hub GUI（**Electron**；subsystem 狀態、日誌、更新通道）。

## Phase 6 — Windows 相容路徑（對齊原始系統計畫）

**決策（2026-07-02）：** 日常 app + 遊戲 + 反作弊 + Vulkan/OpenGL；**預設不使用 per-app sandbox**——app 在共享 SubsystemSession 內互通、共享資料、runtime 協作（`native` 後端）。`container` / `microvm` 僅作可選隔離覆寫。禁止 WinBox / `strawwu-box` 獨立 CLI。規格：`runtime-cooperation.md`、`execution-backends.md`。

| # | 子階段 | 驗收 |
|---|--------|------|
| 6.1 | strawwu-nt（TEB/PEB/PE loader） | stub PE 載入 |
| 6.2 | runtime 協作 + 執行後端（預設 native 共享 session） | `strawwu run` pipe 互通測試；`--backend container` 隔離覆寫 |
| 6.3 | 日常 app（USER32/COM/.NET stub） | 小工具可啟動 |
| 6.4 | 圖形棧（Vulkan + OpenGL） | vkcube/glxgears 於 workload 內 |
| 6.5 | 音訊/輸入（WASAPI/XInput） | 控制器映射 |
| 6.6 | 遊戲路徑（D3D11→VK） | 輕量遊戲可玩 |
| 6.7 | 反作弊矩陣（EAC/BE/Vanguard） | **可正常運行**（Q7）；誠實 PARTIAL |
| 6.8 | Installer（`strawwu install` + repair） | profile 快照/還原 |
| 6.9 | WoW64 | 32-bit stub |
| 6.10 | compat-db + Hub 整合 | 黃金 app CI 矩陣 JSON |
| 6.11 | **裝置驅動代理**（strawwu-device-proxy） | udev 列舉、COM 映射、CUPS/HID、IOCTL 探測表 |
| 6.12 | VFIO 直通 PoC（**可選**） | microvm + 硬體直通實驗文件 |

**Phase 4.6（規格先行）：** `device-driver-proxy.md` 凍結 Tier 1–4 分級與 API 表面（D0）。

規格：`components/specs/execution-backends.md`、`graphics-stack.md`、`anticheat-compat.md`、**`device-driver-proxy.md`**

誠實標 PASS/PARTIAL/FAIL；禁止宣稱完整 Windows 相容。**不載入 Windows `.sys` 進 Linux kernel。**

## 正式版 Release（BLOCKED — 待使用者授權）

- semver MAJOR 須 `>= 1` **僅在使用者明確通知後**
- 預發布產物：`StrawWU-0.3.0-cleanroom-amd64.iso`
- `SHA256SUMS` + `sha256sum -c`
- CI boot/install 證據
- HTML 報告 hermes-deliver
