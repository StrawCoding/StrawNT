# Runtime 協作與互通規格

| 版本 | 0.3.0.0 |
|------|----------------------|
| 日期 | 2026-07-02 |
| 對齊 | `2026-06-29` 系統計畫 Runtime Orchestrator、ADR-0002 |

## 核心決策（2026-07-02）

**不使用 per-app sandbox 作為預設模型。**

Windows 應用預設在同一 **SubsystemSession**（共享 Win32/NT 相容環境）內執行，可：

- 互相通訊（IPC）
- 共享資料與虛擬檔案系統視圖
- 在 runtime 層協作（啟動器 ↔ 遊戲 ↔ 輔助程序）

`container` / `microvm` 僅作為**可選政策覆寫**（不可信 installer、極高風險反作弊探測），不是主架構。

## 分層（與 Ubuntu / runtime 的關係）

```
Ubuntu Linux（Host OS，唯一真實 kernel）
    └── strawwu-runtime（Orchestrator）
            ├── Linux native workloads（ELF，同級）
            └── SubsystemSession（共享 Win32 環境）
                    ├── strawwu-nt（單一 Win32 子系統實例）
                    ├── 多個 Win32 process（可互通）
                    └── strawwu-bridge（seccomp / policy，非第二個 OS）
```

- **Ubuntu** ≠ Windows NT；Ubuntu 是主體。
- **runtime** 調度 Linux 與 Windows app 為**同級 workload**。
- **NT 相容層**是 runtime 底下的一條執行路徑，**不是**與 Ubuntu 平行的第二個 kernel。

## SubsystemSession（共享會話）

每個使用者桌面會話對應一個 `SubsystemSession`：

| 資源 | 共享策略 |
|------|----------|
| 虛擬 `C:\` 基底 | 全系統共用（Program Files、Windows、共用 DLL） |
| Registry | `HKLM` / `HKCR` 共用；`HKCU` 依使用者；`HKCU\Software\<vendor>\<app>` 可 per-app overlay |
| 程序表 | runtime 維護 process graph（parent/child/sibling） |
| IPC 命名空間 | 同 session 內 Named Pipe / Section / ALPC 互通 |
| 剪貼簿 / 拖放 | 與 Linux 桌面整合層共用 |
| GPU / 音訊 | 預設 session 級裝置列舉，供遊戲與 overlay 協作 |

啟動第二個獨立 session 僅在使用者明確要求「隔離執行」或 policy 強制時（`execution_backend: container|microvm`）。

## 互通機制（Phase 4/6 實作目標）

### 6.2.1 IPC Bus（runtime 管理）

`strawwu-runtime` 提供 session 級 IPC 協調，不假裝完整 NT kernel，但對 Win32 app 暴露可互通語意：

| 機制 | 用途 | v3.0 狀態 |
|------|------|-----------|
| Named Pipe (`\\.\pipe\...`) | 啟動器 ↔ 遊戲、服務通訊 | PASS — IPC module 實作 |
| File mapping / Section | 共享記憶體、大型資料 | PASS — NtSection shared memory mapping |
| ALPC / Local RPC 骨架 | COM 前置、系統服務呼叫 | PASS — ALPC port 實作 |
| `SendMessage` / `PostMessage` | 視窗間訊息（同 session HWND） | PASS — WindowManager 訊息佇列 WM_* |
| COM / OLE 骨架 | Office 類、Shell 擴充 | PASS — CoInitialize/CoCreateInstance/ClassRegistry |
| Job Object（邏輯） | runtime 追蹤同 bundle 程序群 | PASS — ProcessGraph spawn/terminate/reparent/siblings |

### 6.2.2 資料共享

- **安裝目錄**：`C:\Program Files\<App>\` 寫入後同 session 其他 app 可讀（符合真實 Windows 語意）。
- **使用者資料**：預設 `C:\Users\<user>\AppData\` 在 session 內可見；per-app 寫入範圍由 profile `filesystem_scope` 控制。
- **執行時合作 bundle**：`strawwu run` 可帶 `--bundle`（例：launcher.exe + game.exe + helper.dll），runtime 將其標記為同一 cooperation group，保證 IPC 與工作目錄一致。

```json
{
  "cooperation_group": "steam-like-launcher",
  "members": ["launcher.exe", "game.exe"],
  "shared_working_dir": "C:\\Games\\Example",
  "ipc_policy": "allow_intra_group"
}
```

### 6.2.3 與 Linux app 協作

同級調度下，Linux app 可透過：

- `strawwu-bridge` Unix socket / D-Bus 閘道
- 共用使用者目錄（`~/` ↔ `C:\Users\...` 映射）
- Hub（Electron）作為觀測面，非執行隔離層

## App Profile（協作預設）

```json
{
  "schema_version": "0.2",
  "app_id": "example-game",
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
    "group": "example-launcher-bundle",
    "allow_spawn_children": true,
    "inherit_registry": true
  },
  "resource_policy": {
    "gpu_mode": "vulkan",
    "syscall_profile": "game"
  }
}
```

`filesystem_scope` 枚舉：

- `session-shared`（**預設**）— 同 SubsystemSession 共享視圖
- `app-overlay` — 僅該 app 的 AppData/Temp overlay（仍允許讀取共享系統 hive）
- `isolated` — 僅在 `execution_backend: container|microvm` 時啟用

## 執行後端與協作的關係

| 後端 | 協作能力 | 使用時機 |
|------|----------|----------|
| `native`（預設） | **完整 session 互通** | 日常 app、遊戲、啟動器+本體、需 COM/IPC 的套件 |
| `container` | 組內互通；與其他 app **預設隔離** | 不可信 installer、使用者明確隔離 |
| `microvm` | VM 內互通；對 host **隔離** | Vanguard 級探測、極高風險 |

**禁止**將 `container` 當作預設後端；遊戲與啟動器必須能在 `native` + `session-shared` 下協作。

## 驗收場景（黃金回歸）

1. **雙程序 pipe**：`writer.exe` 建立 pipe，`reader.exe` 同 session 讀取 → PASS
2. **啟動器鏈**：`launcher.exe` spawn `game.exe`，子程序繼承虛擬 C:\ 與 registry → PASS
3. **共享 DLL**：兩個 app 載入同一 `C:\Program Files\Common\foo.dll` → PASS
4. **COM 骨架**：簡單 In-Proc server 註冊後 client 啟動 → PASS
5. **隔離覆寫**：`strawwu run --backend container untrusted.exe` 無法讀取其他 app pipe → PASS

## 禁止事項

- 禁止 per-app sandbox 作為預設或唯一模型
- 禁止 `WinBox` / `strawwu-box` / `strawwu-sandboxd` 獨立產品線
- 禁止 merge StrawWinBox 原始碼
- 禁止 Wine/Proton 作為底層

## 相關規格

- `execution-backends.md` — native/container/microvm 後端細節
- `graphics-stack.md` — 遊戲與 overlay 共用 GPU
- `anticheat-compat.md` — 反作弊探測與後端覆寫
