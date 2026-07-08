# Golden Apps 啟動驗證規格

| 版本 | 0.7.0.8 |
|------|---------|
| 日期 | 2026-07-08 |
| 對齊 | Q8 決策、`golden-apps.json` |

## 誠實原則

「啟動驗證」在 StrawWU v3.0 **不等於**「可登入帳號 / 可玩遊戲 / 可完整辦公」。定義為：

- 啟動器類：runtime 可載入 stub PE、建立 GUI 視窗、IPC/cooperation 就緒
- Office 類：COM stub + VFS 文件讀寫探測通過
- Hub/compat-db 標示明確等級（最高 B/C，禁止 A）

## 黃金清單（P0）

| ID | 名稱 | 範圍 | 後端 |
|----|------|------|------|
| `office` | Microsoft Office | launch_and_basic_edit | native |
| `steam-launcher` | Steam Client | launcher_only | native |
| `epic-launcher` | Epic Games Launcher | launcher_only | native |
| `delta-force-launcher` | 三角洲行動啟動器 | launcher_only | native |

清單檔：`components/tests/wincompat/golden-apps.json`

## 探測類別

### Office（launch_and_basic_edit）

| Probe | 類別 | 說明 |
|-------|------|------|
| `profile_validate` | profile | AppProfile 驗證 |
| `pe_execute` | runtime | `execute_pe` → Running |
| `gui_smoke` | gui | HWND + PresentBridge |
| `com_stub` | office | ole32 COM stub 可解析 |
| `vfs_doc_open` | office | VFS 文件建立/讀取 |

### 啟動器（launcher_only）

| Probe | 類別 | 說明 |
|-------|------|------|
| `profile_validate` | profile | AppProfile + cooperation group |
| `pe_execute` | runtime | `execute_pe` → Running |
| `gui_smoke` | gui | 登入 UI 視窗模擬 |
| `cooperation_group` | launcher | ProcessGraph bundle |
| `ipc_pipe` | launcher | Named Pipe 互通 |
| `launcher_window` | launcher | 啟動器視窗類別/標題 |

## 等級

| Grade | 含義 |
|-------|------|
| B | 啟動器探測 ≥85% 通過（仍 PARTIAL） |
| C | Office 或啟動器探測部分通過 |
| F | 探測失敗過多 |

**禁止 status=PASS**；overall 固定 PARTIAL（CI worker 無實機二進位）。

## CI 流程

```bash
tests/wincompat/run-golden-apps-verify.sh
# → golden-apps-launch.json
# → merge compat-matrix.json golden_apps_matrix
```

## Hermes 實機擴充

實機 session 可追加 `tests/hw/smoke-wincompat.sh --golden-app <id>`；本 stage CI 以 in-process LaunchProbeEngine 為準。
