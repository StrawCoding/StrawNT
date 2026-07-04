# StrawWU Phase 路線圖（v3.0-cleanroom）

| 版本 | 0.4.0.0 |
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

| # | 子階段 | 驗收 | 狀態（2026-07-04） |
|---|--------|------|---------------------|
| 6.1 | strawwu-nt（TEB/PEB/PE loader） | stub PE 載入 | **FUNCTIONAL** — 完整 PE 解析（含 imports）、VFS（目錄/讀寫/handle）、VMM（alloc/free/protect）、Registry（HKLM/HKCU + overlay + subkey）、COM skeleton（init/create/release）、NtSection（shared memory mapping）、130 tests |
| 6.2 | runtime 協作 + 執行後端（預設 native 共享 session） | `strawwu run` pipe 互通測試；`--backend container` 隔離覆寫 | **FUNCTIONAL** — Orchestrator（session 建立/查詢/終止）、ProcessGraph（spawn/terminate/reparent/suspend/siblings/tree-depth）、SessionRegistry（default/isolated/cleanup）、Executor（PE load→PEB/TEB→IPC→Running）、cooperation groups、37 tests |
| 6.3 | 日常 app（USER32/COM/.NET stub） | 小工具可啟動 | **FUNCTIONAL** — WindowManager（register/create/show/destroy + 訊息佇列 WM_*）、GdiManager（DC/compatible DC/device caps/select object）、COM OLE skeleton（CoInitialize/CoCreateInstance/release + ClassRegistry）、Event objects（signal/reset/wait）、ALPC ports；Win32StubRegistry 含 kernel32/user32/gdi32/ole32 共 53 函式 |
| 6.4 | 圖形棧（Vulkan + OpenGL） | vkcube/glxgears 於 workload 內 | **FUNCTIONAL** — VulkanIcd（instance/surface/device/swapchain/command pool/acquire+present 迴圈）、WglBridge（多 context、GL state machine、50+ GL proc）、PresentBridge（Wayland/X11 + vsync + fps 計算 + resize 驗證）；50 tests |
| 6.5 | 音訊/輸入（WASAPI/XInput） | 控制器映射 | **FUNCTIONAL** — WasapiBridge（PipeWire/PulseAudio 後端、裝置列舉、stream lifecycle、audio buffer read/write、volume control、format negotiation、latency）、XInputSubsystem（4 控制器、button mask、axis deadzone、vibration、capabilities）；23 tests |
| 6.6 | 遊戲路徑（D3D11→VK） | 輕量遊戲可玩 | **FUNCTIONAL** — D3D11Device（resource tracking、shader/input layout/RTV creation、draw call counting、triangle stats、clear RT）、DxgiTranslator（adapter enum、output enum、swap chain + present frame counting）；translation target=vulkan |
| 6.7 | 反作弊矩陣（EAC/BE/Vanguard） | **可正常運行**（Q7）；誠實 PARTIAL | **PASS** — ProbeEngine（stateful 多輪探測、pass rate 追蹤）、8 類 probe category、EAC/BE/Vanguard 各 3+ probes、ProcessScan 模擬、WindowEnum 模擬、AnticheatMatrix（merge/grade/CI JSON）；20 tests。註：Vanguard grade=F（TPM/核心載入限制）為設計邊界，非未實作 |
| 6.8 | Installer（`strawwu install` + repair） | profile 快照/還原 | **FUNCTIONAL** — AppDatabase（install/list/repair/snapshot/restore）、ProfileSnapshot（capture/restore file list + registry）、InstallerType 偵測（exe/msi）、LaunchPipeline 狀態機（6 stages）、CLI parse install/repair |
| 6.9 | WoW64 | 32-bit stub | **FUNCTIONAL** — Wow64Context（auto-detect from PE machine type、System32→SysWOW64 redirect、Program Files redirect）、PeLoader 自動啟用 wow64 for i386 PE |
| 6.10 | compat-db + Hub 整合 | 黃金 app CI 矩陣 JSON | **FUNCTIONAL** — AnticheatMatrix.to_json() + to_ci_json()、DeviceMatrix.to_json()、CompatGrade A/B/C/F、overall_grade()；CLI `strawwu apps list` + `strawwu status` |
| 6.11 | **裝置驅動代理**（strawwu-device-proxy） | udev 列舉、COM 映射、CUPS/HID、IOCTL 探測表 | **FUNCTIONAL** — DeviceEnumerator（by class/tier/path 查詢）、ComPortMapper（Win32 COM↔Linux tty）、HotplugEvent 模擬（add/remove/change）、IoctlHandler（rule-based dispatch + audit log + probe response generation）、10 類裝置 Tier1-4 映射；29 tests |
| 6.12 | VFIO 直通 PoC（**可選**） | microvm + 硬體直通實驗文件 | **PASS** — IOMMU group 掃描、PCI config 讀取、device bind/unbind、MSI/MSI-X 中斷路由、container lifecycle、DMA mapping；29 tests |

**Phase 4.6（規格先行）：** `device-driver-proxy.md` 凍結 Tier 1–4 分級與 API 表面（D0）。

規格：`components/specs/execution-backends.md`、`graphics-stack.md`、`anticheat-compat.md`、**`device-driver-proxy.md`**

誠實標 PASS/PARTIAL/FAIL；禁止宣稱完整 Windows 相容。**不載入 Windows `.sys` 進 Linux kernel。**

## 正式版 Release ✅

- semver MAJOR 須 `>= 1` **僅在使用者明確通知後**
- Release 產物：`StrawWU-0.4.0.0-amd64.iso`（6.1 GB）
- `SHA256SUMS` + `sha256sum -c` ✓
- Boot test：BIOS PASS (110s) + UEFI PASS (100s)
- Cargo test：367/367 PASS
- Git tag：`v0.4.0.0`
- HTML 報告 hermes-deliver ✓
