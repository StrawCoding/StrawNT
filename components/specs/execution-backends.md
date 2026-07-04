# 執行後端規格：native / container / microvm

| 版本 | 0.3.0.0-draft |
|------|----------------------|
| 日期 | 2026-07-02 |
| 對齊 | `2026-06-29` 系統計畫 Phase 6、ADR-0002 Runtime Orchestration |

## 目標

Windows 應用由 **`strawwu-runtime`（Orchestrator）** 統一編排。預設在 **共享 SubsystemSession** 內執行（`execution_backend: native`），app 之間可互通、共享資料、runtime 層協作——**不使用 per-app sandbox 作為預設**。

`container` / `microvm` 為**可選政策覆寫**（隔離不可信或極高風險 workload），由 runtime 內建，不是獨立 Docker 克隆 daemon。詳見 `runtime-cooperation.md`。

**禁止** `WinBox` / `winbox` 命名（與 StrawWinBox 專案區隔）；禁止 merge StrawWinBox 原始碼。

## 架構（對齊原始計畫）

```
                    ┌─────────────────────────┐
                    │  strawwu-runtime        │
                    │  Orchestrator           │
                    │  - SubsystemSession     │
                    │  - app profile / IPC    │
                    │  - 選 execution_backend │
                    └───────────┬─────────────┘
                                │ RuntimeSession API
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌──────▼──────┐ ┌───────▼────────┐
    │  strawwu-nt        │ │ Linux apps │ │ strawwu-hub    │
    │  共享 Win32 子系統  │ │ (native)   │ │ (Electron)     │
    │  多 process 互通   │ │            │ │                │
    └─────────┬──────────┘ └────────────┘ └────────────────┘
              │ BridgeRequest ABI
    ┌─────────▼──────────────────────────┐
    │  strawwu-bridge（kernel 橋接）        │
    │  seccomp / policy（非第二個 OS）      │
    └─────────┬──────────────────────────┘
              │
    ┌─────────▼────────┐
    │  Linux Kernel    │
    └──────────────────┘
```

### execution_backend 三種策略

| 後端 | 用途 | 協作 / 隔離 | v3.0 預期 | 預設？ |
|------|------|-------------|-----------|--------|
| `native` | 日常 app、遊戲、啟動器+本體、需 IPC 的套件 | **共享 session，app 互通** | PARTIAL | **是** |
| `container` | 不可信 installer、使用者要求隔離 | 組內可互通；對其他 app 隔離 | PARTIAL | 否（覆寫） |
| `microvm` | 極高風險反作弊探測、不可信核心邏輯 | VM 內互通；對 host 隔離 | PARTIAL | 否（覆寫） |

Orchestrator **不實作** Win32 syscall 語意（屬 strawwu-nt）；**不繞過** NT 直接 ioctl bridge（除 ResourcePolicy）。

## App Profile（schema 對齊 profile-v2）

```json
{
  "schema_version": "0.2",
  "app_id": "notepad-plus",
  "runtime_kind": "win32",
  "execution_backend": "native",
  "session_mode": "shared",
  "permissions": {
    "network": true,
    "gpu": true,
    "filesystem_scope": "session-shared",
    "ipc_scope": "session"
  },
  "cooperation": {
    "allow_spawn_children": true,
    "inherit_registry": true
  },
  "resource_policy": {
    "gpu_mode": "vulkan",
    "syscall_profile": "daily"
  }
}
```

`syscall_profile` 枚舉：`daily` | `game` | `anticheat`（影響 bridge seccomp 與探測回應表）。

## native 後端（預設，協作執行）

- 所有 app 進入同一 **SubsystemSession**
- 共享虛擬 `C:\` 基底、`HKLM`/`HKCR`、session 級 IPC 命名空間
- strawwu-launcher 注入 PE、建立 TEB/PEB；runtime 維護 process graph
- 子程序（啟動器 spawn 遊戲）預設繼承環境與 cooperation group
- 圖形經 `strawwu-graphics`（Vulkan/OpenGL，見 `graphics-stack.md`）
- bridge seccomp 依 profile 收緊，**不**切斷同 session 的合法 IPC

## container 後端（可選覆寫）

僅在 profile 或 CLI 明確指定時啟用：

- pid/mnt/net 等 namespace + cgroup；per-app overlay（C:\、registry）
- **預設切斷**與其他 session app 的 IPC；組內 `--bundle` 仍可互通
- 圖形、音訊仍經 strawwu-graphics / audio-bridge 轉發
- Hub 顯示 workload 狀態與 compat-db 等級

## microvm 後端（可選覆寫）

- runtime 依 profile 自動或使用者指定 `--backend microvm`
- GUI/剪貼簿/音訊轉發使 app 仍像桌面整合視窗
- 高風險 / 反作弊類 app 可選 microvm；**非**預設路徑
- 不得讀取未授權 home 目錄

## CLI（統一 strawwu，禁止 strawwu-box）

```bash
strawwu install setup.exe
strawwu run app.exe                              # 預設 native + shared session
strawwu run --bundle launcher.exe,game.exe       # cooperation group
strawwu run --backend container untrusted.exe    # 明確隔離覆寫
strawwu run --backend microvm --profile anticheat launcher.exe
strawwu apps list
strawwu profile inspect <app-id>
strawwu profile export <app-id>
strawwu repair <app-id>                          # 重設 app overlay（不影響其他 app）
```

## 與 Hub（Electron）整合

- 列出已安裝 app、execution_backend、session_mode
- 顯示 cooperation group 與 process graph
- 一鍵切換 GPU 模式（Vulkan/OpenGL）、修復/重設 per-app overlay
- 顯示 compat-db A/B/C/F 與反作弊探測結果

## 禁止事項

- 禁止 per-app sandbox 作為預設或唯一架構
- 禁止使用 `WinBox` / `winbox` 作為產品或 API 名稱
- 禁止 merge StrawWinBox 原始碼
- 禁止獨立 `strawwu-sandboxd` + `strawwu-box` 平行於 runtime 的第二套 CLI
- 禁止 Wine/Proton 作為底層執行引擎

## 非目標（v3.0）

- 完整 Hyper-V 相容
- 100% 內核模式驅動簽章通過
- 所有反作弊可排位對戰
