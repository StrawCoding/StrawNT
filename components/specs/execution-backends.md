# 執行後端規格：wine / native(legacy) / container / microvm

| 版本 | 0.7.1（NTW0 pivot） |
|------|----------------------|
| 日期 | 2026-08-07（原 2026-07-02；契約翻轉） |
| 對齊 | Wine pivot ADR、`2026-06-29` Phase 6 歷史、ADR-0002 Runtime Orchestration |

> **契約翻轉（2026-08-07／NTW0）：** 產品預設 `execution_backend=wine`／`engine=proton-ge`（**powered by Wine**）。舊「禁 Wine／Proton」與「native 為唯一預設」已**廢止**。見 `docs/decisions/2026-08-07-wine-pivot.md`。

## 目標

Windows 應用由 **`strawnt`／runtime 編排層** 統一啟動。產品預設經 **Wine／Proton-GE**（`execution_backend: wine`）在 prefix 內執行；app 之間可互通（同 prefix；跨 prefix IPC 見 NTW4）——**不使用 per-app sandbox 作為預設**。

`native`（自研 PE）僅 **legacy／research**（`STRAWNT_LEGACY_NATIVE=1`，unsupported）。`container` / `microvm` 為**可選政策覆寫**（隔離不可信或極高風險 workload），不是獨立 Docker 克隆 daemon。詳見 `runtime-cooperation.md`。

**禁止** `WinBox` / `winbox` 命名（與 StrawWinBox 專案區隔）；禁止 merge StrawWinBox 原始碼；禁止將 Wine 靜默改名為自研 PE。

## 架構（對齊 Wine pivot）

```
                    ┌─────────────────────────┐
                    │  strawnt CLI + Hub      │
                    │  (Electron)             │
                    │  - prefix / recipes     │
                    │  - App Manager (NTW5+)  │
                    │  - 選 execution_backend │
                    └───────────┬─────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
    ┌─────────▼────────┐ ┌──────▼──────┐ ┌───────▼────────┐
    │  Proton-GE / Wine │ │ container / │ │ legacy native  │
    │  （產品預設）      │ │ microvm 覆寫│ │ STRAWNT_LEGACY │
    │  prefix 互通      │ │             │ │ _NATIVE=1      │
    └─────────┬──────────┘ └────────────┘ └────────────────┘
              │
    ┌─────────▼────────┐
    │  Linux x86_64    │
    │  Wayland/X11     │
    └──────────────────┘
```

歷史 native Orchestrator／SubsystemSession 圖見 git 歷史與 `archive/native-pe/`；不作產品預設。

### execution_backend 策略

| 後端 | 用途 | 協作 / 隔離 | 狀態 | 預設？ |
|------|------|-------------|------|--------|
| `wine` | 旗艦產品路徑（Proton-GE vendored；可選 system-wine 風味） | **同 prefix 互通**；跨 prefix 見 NTW4 | NTW1+ vendor／runner | **是** |
| `native` | 歷史自研 PE／研究 | 共享 SubsystemSession | **legacy／archive** | 否（`STRAWNT_LEGACY_NATIVE=1`） |
| `container` | 不可信 installer、使用者要求隔離 | 組內可互通；對其他 app 隔離 | 可選覆寫 | 否 |
| `microvm` | 極高風險反作弊探測、不可信核心邏輯 | VM 內互通；對 host 隔離 | 可選覆寫 | 否 |

旗艦路徑以 Wine／GE 為基板；legacy native Orchestrator 保留 git 歷史，不作產品預設。

## App Profile（schema 對齊 profile-v2）

```json
{
  "schema_version": "0.2",
  "app_id": "notepad-plus",
  "runtime_kind": "win32",
  "execution_backend": "wine",
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

## wine 後端（產品預設）

- 經 **Proton-GE**（vendored；大檔 git-lfs）或可選 system-wine 風味執行
- Prefix 預設 `~/.local/share/strawnt/`；誠實標示 **powered by Wine**
- 圖形／音訊經 DXVK／vkd3d／PipeWire 等（NTW1–NTW3）
- 不得宣稱完整 Windows／排位／官方反作弊通過

## native 後端（legacy／research）

- 所有 app 進入同一 **SubsystemSession**（歷史設計）
- 共享虛擬 `C:\` 基底、`HKLM`/`HKCR`、session 級 IPC 命名空間
- 僅經 `STRAWNT_LEGACY_NATIVE=1`（**unsupported**）；不作產品預設
- 圖形經 `strawwu-graphics`（Vulkan/OpenGL，見 `graphics-stack.md`）歷史路徑

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
strawnt install setup.exe
strawnt run app.exe                              # 預設 wine / proton-ge
strawnt run --bundle launcher.exe,game.exe       # cooperation group（同 prefix）
strawnt run --backend container untrusted.exe    # 明確隔離覆寫
strawnt run --backend microvm --profile anticheat launcher.exe
STRAWNT_LEGACY_NATIVE=1 strawnt run app.exe      # legacy native（unsupported）
strawnt apps list
strawnt profile inspect <app-id>
strawnt profile export <app-id>
strawnt repair <app-id>                          # 重設 app overlay（不影響其他 app）
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
- 禁止將 Wine／Proton-GE **靜默改名**為自研 PE／完整 Windows（必須標 **powered by Wine**）
- 禁止宣稱排位／官方反作弊簽章通過

## 非目標

- 完整 Hyper-V 相容／完整 Windows OS
- 100% 內核模式驅動簽章通過
- 所有反作弊可排位對戰
- 以 native PE 作為產品預設（已 soft-reset／legacy）
