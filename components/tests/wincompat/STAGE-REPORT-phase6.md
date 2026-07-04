# Phase 6 Stage Report — phase6-wincompat

**版本**: 0.3.0-cleanroom  
**階段**: 6/8 (phase6-wincompat)  
**日期**: 2026-07-04  
**狀態**: 待 Hermes 驗收

---

## 驗證結果總覽

| 驗證命令 | 結果 | 驗證時間 |
|---------|------|----------|
| `make -C components test-wincompat` | PASS | 2026-07-04 02:10 UTC-4 |
| `make -C components test-execution-backends` | PASS | 2026-07-04 02:10 UTC-4 |
| `make -C components test-graphics-vulkan` | PASS | 2026-07-04 02:10 UTC-4 |
| `make -C components test-graphics-opengl` | PASS | 2026-07-04 02:10 UTC-4 |
| `make -C components test-anticheat-matrix` | PASS | 2026-07-04 02:10 UTC-4 |
| `make -C components test-device-proxy` | PASS | 2026-07-04 02:10 UTC-4 |

---

## Sub-Stage 詳細狀態

| ID | 子階段 | 狀態 | 說明 |
|----|--------|------|------|
| 6.1 | strawwu-nt (TEB/PEB/PE loader) | PARTIAL | PE 解析（MZ/PE/COFF/section）、TEB/PEB 建立、NT syscall dispatch stubs（14 syscall）；42 tests pass |
| 6.2 | Execution backends + runtime cooperation | PARTIAL | Native 共享 SubsystemSession 預設；container/microvm 覆寫；Named Pipe IPC（namespace/direction/connect）；Orchestrator 管理 session 與 process graph；33 tests pass |
| 6.3 | Daily apps (USER32/GDI32/COM) | PARTIAL | kernel32（24 func）/user32（15 func）/gdi32（10 func）/ole32（4 func）stub registry；resolve→Success/Stub/NotImplemented |
| 6.4 | Graphics: Vulkan (DXGI→VK) | PARTIAL | VulkanIcd 1.3.0 stub（surface extensions）, DXGI factory/adapter/swapchain, PresentBridge（resolution/fullscreen） |
| 6.4b | Graphics: OpenGL (wgl→GLX/EGL) | PARTIAL | WglBridge 支援 GLX/EGL backend, GL 2.1 subset, wglGetProcAddress（11 GL functions） |
| 6.5 | Audio/Input (WASAPI/XInput) | PARTIAL | WASAPI bridge→PipeWire（render+capture, stream lifecycle）; XInput 4-controller（connect/button/vibration） |
| 6.6 | Game path (D3D11→VK) | PARTIAL | D3D11 device/buffer/texture2D/RTV/present→Vulkan translation, feature level 9.1–11.1 |
| 6.7 | Anti-cheat matrix (EAC/BE/Vanguard) | PARTIAL | EAC: C grade（driver stub, kernel callback stub, DLL integrity partial）; BE: C grade（scan intercept, debugger bypass）; Vanguard: F grade（TPM stub 失敗, kernel driver 政策拒絕） |
| 6.8 | Installer (strawwu install + repair) | PARTIAL | AppDatabase（install/list/uninstall）, installer type detection（MSI/EXE/NSIS/InnoSetup）, profile snapshot/restore |
| 6.9 | WoW64 (32-bit PE path) | PARTIAL | Wow64Context, System32→SysWOW64 redirect, Program Files (x86) path mapping |
| 6.10 | compat-db + Hub integration | PARTIAL | compat-matrix.json 生成, A/B/C/F 評級系統, 13 sub-stage 矩陣 |
| 6.11 | device-proxy | PARTIAL | 10-class device map（GPU/Audio/Keyboard/Mouse/Gamepad/Serial/Printer/HID/Network/Storage）; IOCTL handler allow/deny/stub/audit; device-matrix.json |
| 6.12 | VFIO passthrough PoC | PARTIAL | 實驗性文件（vfio-passthrough-poc.md），無 runtime code；納入 Q2 PoC 計畫 |

---

## 架構決策（已落實）

1. **預設 Native 共享 SubsystemSession** — 所有 Win32 app 共享同一 session（registry/filesystem/IPC），實現互通/協作
2. **Container/Microvm 僅覆寫** — 通過 AppProfile.execution_backend 設定，isolated app 建立獨立 session
3. **禁止 WinBox/sandbox** — 不使用 strawwu-box，native 是預設
4. **誠實 PARTIAL** — 所有子階段明確標記 PARTIAL，不虛報 PASS
5. **Ubuntu 為唯一真實 kernel** — NT 相容層是 runtime 底下的執行路徑，非第二個 OS
6. **Seccomp policy 分級** — daily/game/anticheat 三種 syscall profile

---

## 測試統計

- **strawwu-runtime**: 17 tests (session lifecycle, process graph, orchestrator, cooperation group)
- **strawwu-bridge**: 10 tests (ABI encode/decode, policy seccomp, transport socket)
- **strawwu-nt**: 42 tests (PE parser, TEB/PEB, ntdll dispatch, IPC Named Pipe, win32_stubs registry, WoW64, installer, registry)
- **strawwu-graphics**: 22 tests (vulkan ICD, dxgi factory, opengl WGL, d3d11 device, present bridge)
- **strawwu-audio**: 9 tests (wasapi init/enumerate/stream, xinput connect/button/vibration)
- **strawwu-anticheat**: 11 tests (matrix generate/honest/json, probes EAC/BE/Vanguard)
- **strawwu-device-proxy**: 11 tests (devices map/subsystem/honest, ioctl rules, device matrix)
- **Total**: 122 unit tests, all pass

---

## 元件結構

```
components/
├── Cargo.toml              (workspace: 8 crates, v0.3.0)
├── strawwu-runtime/        (Orchestrator + SubsystemSession + ProcessGraph + AppProfile)
├── strawwu-bridge/         (ABI protocol + Seccomp policy + Unix socket transport)
├── strawwu-nt/             (PE parser + TEB/PEB + ntdll + win32_stubs + WoW64 + IPC + installer + registry)
├── strawwu-graphics/       (Vulkan ICD + DXGI + OpenGL WGL + D3D11→VK + PresentBridge)
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
- `components/strawwu-runtime/` ✓
- `components/strawwu-nt/` ✓
- `components/strawwu-graphics/` ✓
- `components/strawwu-device-proxy/` ✓
- `components/tests/wincompat/output/compat-matrix.json` ✓
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

Phase 6 所有 6 個驗證命令通過，122 個 unit test 全部 PASS。整體狀態為 **PARTIAL**（誠實報告：所有 13 個子階段均為 stub/mock 層實作，尚未接入真實 Windows 二進位執行）。

**無產品決策阻塞。建議 Hermes 進行 trigger-verify。**
