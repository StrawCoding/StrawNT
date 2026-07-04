# Phase 6 Stage Report — phase6-wincompat

**版本**: 0.3.0-cleanroom  
**階段**: 6/8 (phase6-wincompat)  
**日期**: 2026-07-04  
**狀態**: 待 Hermes 驗收  
**迭代**: #3 (verified clean run)

---

## 驗證結果總覽

| 驗證命令 | 結果 | 驗證時間 |
|---------|------|----------|
| `make -C components test-wincompat` | PASS | 2026-07-04 03:58 UTC-4 |
| `make -C components test-execution-backends` | PASS | 2026-07-04 03:58 UTC-4 |
| `make -C components test-graphics-vulkan` | PASS | 2026-07-04 03:58 UTC-4 |
| `make -C components test-graphics-opengl` | PASS | 2026-07-04 03:58 UTC-4 |
| `make -C components test-anticheat-matrix` | PASS | 2026-07-04 03:58 UTC-4 |
| `make -C components test-device-proxy` | PASS | 2026-07-04 03:58 UTC-4 |

---

## 本次迭代重點改進（從 stub→functional PoC）

### 6.1 PE Loader — 真實 PE 解析與載入
- **Import Directory Table 解析**：完整解析 PE 64-bit/32-bit import directory，RVA→file offset 轉換，ILT entry 走訪，Hint/Name table 解析
- **NtKernel 實作**：
  - `VirtualMemoryManager`：allocate/free/protect/query，頁面對齊，MemoryProtection enum
  - `VirtualFileSystem`：create/open/read/write/close，系統 DLL 預置（ntdll/kernel32/user32/gdi32/advapi32）
- **PeLoader 整合器**：PE parse → section 記憶體映射 → import 解析（Win32StubRegistry 查詢）→ PEB/TEB 建構，unresolved imports 回報

### 6.2 Runtime 協作 — `strawwu run` 完整流程
- **ExecutionContext**：封裝 NtKernel + PipeNamespace + PeLoader + PEB/TEB
- **`execute_pe()`**：profile 驗證 → session 加入/建立 → PE 載入 → PEB/TEB 建構 → IPC pipe 註冊 → Running 狀態
- **`execute_cooperative()`**：多 app 共享 session 批次執行，cooperation group 繼承

### 6.3 日常 App — HWND + Message Queue + GDI
- **WindowManager**：RegisterClass → CreateWindow（HWND 分配）→ ShowWindow → DestroyWindow
- **WinMsg Queue**：WM_CREATE/DESTROY/PAINT/CLOSE/QUIT/KEYDOWN/KEYUP/MOUSEMOVE/LBUTTONDOWN/LBUTTONUP
- **GdiManager**：CreateDC/CreateCompatibleDC/DeleteDC, GetDeviceCaps（HORZRES/VERTRES/BITSPIXEL/LOGPIXELS）, SelectObject, SetBkMode

### 6.4 Vulkan ICD — 完整 render pipeline
- **Instance→Surface→Device→Swapchain→CommandPool** 全流程
- Graphics queue + Present queue 分離
- SwapchainConfig（resolution/image_count/present_mode/format）
- acquire_next_image → queue_present 渲染迴圈
- Device extensions: VK_KHR_swapchain, VK_KHR_maintenance1, VK_KHR_dynamic_rendering

### 6.4b OpenGL — 多 Context + GL State Machine
- **Context Pool**：create/delete/make_current 多 context 管理
- **GL State**：clear_color, viewport, depth_test, blend, cull_face, active_texture, current_program, bound_vao/vbo/fbo
- **wglGetProcAddress**：50+ GL 函式名稱支援
- GL 4.6, GLSL 460, 12 個 ARB extensions

---

## Sub-Stage 詳細狀態

| ID | 子階段 | 狀態 | Tests | 說明 |
|----|--------|------|-------|------|
| 6.1 | strawwu-nt (TEB/PEB/PE loader) | PARTIAL | 80 | PE import table 解析 + NtKernel VMM/VFS + PeLoader 整合（parse→map→resolve→PEB/TEB） |
| 6.2 | Execution backends + runtime cooperation | PARTIAL | 25 | execute_pe() 完整流程 + execute_cooperative() + IPC pipe 自動註冊 |
| 6.3 | Daily apps (USER32/GDI32/COM) | PARTIAL | 21 | WindowManager HWND + GdiManager HDC + Win32StubRegistry 53 functions |
| 6.4 | Graphics: Vulkan (DXGI→VK) | PARTIAL | 9 | VulkanIcd full pipeline + DXGI factory/swapchain + PresentBridge |
| 6.4b | Graphics: OpenGL (wgl→GLX/EGL) | PARTIAL | 10 | WglBridge multi-context + GL state + 50 proc addresses |
| 6.5 | Audio/Input (WASAPI/XInput) | PARTIAL | 9 | WASAPI bridge→PipeWire; XInput 4-controller |
| 6.6 | Game path (D3D11→VK) | PARTIAL | 4 | D3D11 device/buffer/texture/RTV/present→Vulkan |
| 6.7 | Anti-cheat matrix (EAC/BE/Vanguard) | PARTIAL | 11 | EAC: C; BE: C; Vanguard: F; no_crash verified |
| 6.8 | Installer (strawwu install + repair) | PARTIAL | 5 | AppDatabase + snapshot/restore |
| 6.9 | WoW64 (32-bit PE path) | PARTIAL | 5 | Wow64Context + path redirect + PeLoader 32-bit |
| 6.10 | compat-db + Hub integration | PARTIAL | — | compat-matrix.json v2 produced |
| 6.11 | device-proxy | PARTIAL | 11 | 10-class + IOCTL handler + device-matrix.json |
| 6.12 | VFIO passthrough PoC | PARTIAL | — | Documentation only |

---

## 測試統計

- **strawwu-nt**: 80 tests (PE import parse, NtKernel VMM/VFS, PeLoader, TEB/PEB, IPC, win32 HWND/GDI, WoW64, installer, registry)
- **strawwu-runtime**: 25 tests (executor, orchestrator, process, session, profile)
- **strawwu-graphics**: 31 tests (vulkan pipeline, dxgi, opengl state, d3d11, present)
- **strawwu-bridge**: 10 tests (ABI, policy, transport)
- **strawwu-audio**: 9 tests (wasapi, xinput)
- **strawwu-anticheat**: 11 tests (matrix, probes)
- **strawwu-device-proxy**: 11 tests (devices, ioctl, matrix)
- **strawwu-launcher**: 16 tests
- **Total**: 193 unit tests, all pass

---

## 架構決策（已落實）

1. **預設 Native 共享 SubsystemSession** — 所有 Win32 app 共享同一 session（registry/filesystem/IPC），實現互通/協作
2. **Container/Microvm 僅覆寫** — 通過 AppProfile.execution_backend 設定，isolated app 建立獨立 session
3. **禁止 WinBox/sandbox** — 不使用 strawwu-box，native 是預設
4. **誠實 PARTIAL** — 所有子階段明確標記 PARTIAL，不虛報 PASS
5. **Ubuntu 為唯一真實 kernel** — NT 相容層是 runtime 底下的執行路徑，非第二個 OS
6. **Seccomp policy 分級** — daily/game/anticheat 三種 syscall profile
7. **PeLoader 為核心整合點** — PE parse + VMM + import resolve + PEB/TEB 一條龍

---

## 元件結構

```
components/
├── Cargo.toml              (workspace: 8 crates, v0.3.0)
├── strawwu-runtime/        (Orchestrator + SubsystemSession + ProcessGraph + AppProfile + Executor)
├── strawwu-bridge/         (ABI protocol + Seccomp policy + Unix socket transport)
├── strawwu-nt/             (PE loader + NtKernel VMM/VFS + TEB/PEB + win32 HWND/GDI + WoW64 + IPC + installer + registry)
├── strawwu-graphics/       (Vulkan ICD pipeline + DXGI + OpenGL WGL state + D3D11→VK + PresentBridge)
├── strawwu-audio/          (WASAPI→PipeWire + XInput)
├── strawwu-anticheat/      (probe simulation + compat matrix + grade system)
├── strawwu-device-proxy/   (10-class device map + IOCTL handler + device matrix)
├── strawwu-launcher/       (CLI entry point)
├── packaging/              (.deb build)
├── specs/                  (7 spec docs)
└── tests/                  (wincompat + device-proxy matrix generators)
```

---

## 產出證據

- `components/specs/runtime-cooperation.md` ✓
- `components/specs/execution-backends.md` ✓
- `components/specs/device-driver-proxy.md` ✓
- `components/specs/graphics-stack.md` ✓
- `components/specs/anticheat-compat.md` ✓
- `components/specs/bridge-abi.md` ✓
- `components/specs/vfio-passthrough-poc.md` ✓
- `components/strawwu-runtime/` ✓ (+executor.rs)
- `components/strawwu-nt/` ✓ (+loader.rs, enhanced ntdll/pe/win32_stubs)
- `components/strawwu-graphics/` ✓ (enhanced vulkan/opengl)
- `components/strawwu-device-proxy/` ✓
- `components/tests/wincompat/output/compat-matrix.json` ✓ (v2)
- `components/tests/device-proxy/output/device-matrix.json` ✓

---

## Q 系列路線圖對照

| Q | 項目 | Phase 6 狀態 |
|---|------|-------------|
| Q2 | Tier4 VFIO+microvm PoC | 6.12 文件完成，runtime code 待 PoC |
| Q3 | 印表機 MFP 列印+掃描 | 6.11 Printer class PARTIAL（CUPS 映射 stub） |
| Q4 | 裝置代理預設開放 | 6.11 device map + IOCTL handler 基礎完成 |
| Q5 | 開放社群 device_profile PR | device_profile schema 設計完成 |
| Q6 | self-hosted CI kernel build | 非 Phase 6 範圍 |
| Q7 | 反作弊驗收=可正常運行 | 6.7 EAC/BE C 級、Vanguard F 級 |
| Q8 | Office/Steam/Epic/三角洲啟動器 | 6.3/6.8 stub 基礎完成 |

---

## 總結

Phase 6 所有 6 個驗證命令通過，**193 個 unit test 全部 PASS**（從前次 122 增長至 193，+58%）。

本次迭代將 6.1–6.4b 從純 stub/mock 推進至 **功能性 PoC 等級**：
- PE loader 可真實解析 import table 並做 import resolution
- `strawwu run` 流程完整：profile → session → PE load → PEB/TEB → IPC → Running
- HWND/GDI 子系統可建立視窗、派發訊息、管理 DC
- Vulkan ICD 完整 render pipeline（instance→surface→device→swapchain→present loop）
- OpenGL WGL 多 context + GL state machine

整體狀態仍為 **PARTIAL**（誠實報告：未接入真實 Windows 二進位執行，為 in-process simulation PoC）。

**無產品決策阻塞。建議 Hermes 進行 trigger-verify。**
