# 裝置驅動代理層規格

| 欄位 | 值 |
|------|-----|
| 狀態 | **APPROVED — 已併入 v3.0-cleanroom 計畫** |
| 版本 | 0.3.0-cleanroom |
| 日期 | 2026-07-02 |
| 對齊 | `runtime-cooperation.md`、`execution-backends.md`、`anticheat-compat.md`、Phase 2 `strawwu_ipc` |

## 問題陳述

在 Linux 主體 OS 上，若某硬體**僅提供 Windows 驅動**（常見 `.sys` kernel driver 或專屬 Win32 IOCTL 協定），Win32 應用無法像在 Windows 上一樣直接 `NtLoadDriver` 後使用裝置。

StrawWU **不載入 Windows kernel driver 進 Linux kernel**。解法為 **userspace 代理層 + Linux 原生驅動優先 + 可選硬體直通**，而非假裝能跑 `.sys`。

## 核心原則

1. **Ubuntu Linux kernel 是唯一真實核心** — 不 merge Windows kernel、不載入 `.sys`。
2. **代理，不是模擬整個 Windows 驅動模型** — 針對 Win32 可見的 device API 做翻譯。
3. **預設共享 SubsystemSession** — 裝置在 session 內可被多個 Win app 協作使用。
4. **誠實分級** — compat-db 標 A/B/C/F；無法支援的裝置不宣稱可用。

## 元件：strawwu-device-proxy

```
Win32 App
  → SetupAPI / CreateFile(\\.\...) / DeviceIoControl
  → strawwu-nt（\Device\ 命名空間、handle 語意）
  → strawwu-device-proxy（翻譯 + 模擬 + 政策）
  → strawwu-runtime（裝置指派、session 共享、profile 權限）
  → strawwu-bridge（ioctl 審計、seccomp、ResourcePolicy）
  → Linux（udev, libusb, CUPS, evdev, DRM/KMS, tty, socketCAN…）
```

| 元件 | 角色 |
|------|------|
| strawwu-runtime | 決定哪個 app 可用哪個裝置；session 級裝置列舉 |
| strawwu-nt | Win32 device namespace，不實作真實硬體驅動 |
| strawwu-device-proxy | API 翻譯與虛擬裝置節點 |
| strawwu-bridge | 審計、限制危險 ioctl、可選轉發至 `/dev/*` |
| strawwu-hub | 顯示裝置對應表、compat 等級、疑難排解 |

## 四層解法（依難度遞增）

### Tier 1 — Linux 已有驅動（首選）

- `\\.\COMn` → `/dev/ttyUSB*`
- `SetupDiGetClassDevs` 列舉 → udev 屬性 + 別名表
- 印表機 spooler API → CUPS IPP/backend
- GPU/音訊由 `graphics-stack` / `audio-bridge` 處理

**目標：** v0.3 可達 PARTIAL；日常周邊優先。

### Tier 2 — Userspace 重實作協定

- libusb 在 Linux 上直接通訊
- proxy 實作 Win32 期望的 IOCTL 子集
- 裝置專用 profile（`device_profile.json`）

**目標：** 逐裝置擴充；compat-db 逐項登記。

### Tier 3 — 虛擬裝置 / 探測回應

- App 僅探測驅動是否存在（Npcap、虛擬化安裝器、反作弊 driver probe）
- 可配置 **IOCTL 回應表**（對齊 `anticheat-compat.md`）
- 高風險可強制 `execution_backend: container|microvm`

**目標：** 不崩潰 + 誠實 PARTIAL。

### Tier 4 — 硬體直通 + 隔離 VM（最後手段）

- VFIO / USB passthrough → microvm 內極小 Windows guest
- compat-db 等級 C 或 F；**不進 v3.0 MVP**

## 路線圖對照（已併入主計畫）

| 子階段 | 內容 | 插入 Phase | 依賴 | 產物 |
|--------|------|------------|------|------|
| D0 | 規格凍結 + compat 分級 | **4.6** | runtime 骨架 | 本文件 v1.0 |
| D1 | udev→Win32 列舉 + COM 映射 | **6.11** | strawwu-nt handle 表 | `strawwu-device-proxy` crate |
| D2 | DeviceIoControl 轉發框架 | **6.11** | strawwu-bridge | ioctl audit log |
| D3 | 印表機/CUPS + USB HID | **6.11** | D1 | 黃金周邊測試 |
| D4 | IOCTL 探測表（installer/AC） | **6.11**（與 6.7 協同） | anticheat-compat | Hub 顯示 |
| D5 | VFIO 直通 PoC | **6.12（可選）** | microvm 後端 | 實驗文件 |

## 裝置類型矩陣

| 類型 | Linux 路徑 | Proxy 策略 | v3.0 目標 |
|------|------------|------------|-----------|
| GPU | DRM/KMS + Vulkan/GL | graphics-stack | PARTIAL |
| 音訊 | PipeWire/Pulse | WASAPI bridge | PARTIAL |
| 鍵鼠/手把 | evdev | XInput/DirectInput 映射 | PARTIAL |
| 序列/COM | ttyUSB/ttyACM | COM 埠映射 | PARTIAL |
| 印表機 | CUPS | Win32 spooler 子集 | PARTIAL |
| 一般 USB HID | hidraw | SetupAPI 列舉 | PARTIAL |
| 自訂 USB IOCTL | libusb | Tier 2 逐裝置 | C |
| 網路抓包 (Npcap) | 不載入 .sys | Tier 3 探測回應 | F/C |
| 虛擬化 (VBox/VMware) | KVM 原生 | 引導 Linux 方案 | F |
| 反作弊 kernel driver | 不載入 | Tier 3 探測矩陣 | PARTIAL/F |
| 僅 Windows .sys 專業儀器 | 無 | Tier 4 或 F | F |

## API 表面（Phase A 最小集）

- `CreateFileW` on `\\.\PhysicalDrive*` / `\\.\COM*` / `\\.\pipe\`
- `DeviceIoControl` — 可翻譯子集 + 明確 `ERROR_NOT_SUPPORTED`
- `SetupDi*` 列舉、安裝精靈攔截（kernel driver 安裝 → 引導 Tier 1/2 或拒絕）
- `NtLoadDriver` / `NtUnloadDriver` — **政策拒絕**（audit 記錄）
- Registry `HKLM\SYSTEM\CurrentControlSet\Services\` — 虛擬 hive

## Phase 2 協同（strawwu_ipc）

`strawwu_ipc` 核心模組提供：

- 假 `\\.\`-style 裝置節點（userspace 可見，非真 kernel driver）
- IOCTL 回應表（可配置 per-profile）
- 不宣稱通過官方簽章驗證

## 驗收

```bash
make -C components test-device-proxy
make -C components test-anticheat-matrix   # D4 協同
```

證據：`components/tests/device-proxy/output/device-matrix.json`

## 風險與誠實邊界

- **無法通用執行任意 .sys** — 架構決策，非暫時 bug。
- **簽章驅動 / PatchGuard 語意** — 不實作；安全軟體類 app 多為 F。
- **DMA 直硬體** — bridge 嚴格政策，避免 Win app 攻擊 host。

## 開放問題

1. 是否接受 Tier 4（microvm + Windows guest）作為企業選項？
2. 印表機 MVP 要支援到哪一級（僅列印 vs 掃描一體）？
3. USB 自訂 IOCTL 裝置是否開放社群貢獻 `device_profile`？
4. 裝置代理是否預設對所有 Win app 開放，或須 Hub 逐項授權？
