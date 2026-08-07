# 反作弊相容矩陣規格

| 版本 | 0.4.0.0 |
|------|----------------------|
| 對齊 | ADR-0001 範圍、runtime policy |

## 誠實原則

「相容」在 StrawWU v3.0 **不等於**「可排位對戰」。定義為：反作弊探測執行時程序不立即崩潰，且 Hub/compat-db 標示明確等級。

## 執行策略與後端

> **NTW0：** 產品預設 `execution_backend=wine`。下表「native」欄位為歷史／legacy 建議；旗艦路徑改經 Wine／GE prefix。禁宣稱排位／官方 AC 通過。

| 反作弊類型 | 建議 execution_backend | 說明 |
|------------|------------------------|------|
| 無 / 輕量 | **`wine`（產品預設）**；legacy `native` | 日常 app、單機遊戲、啟動器+本體 |
| EAC / BattlEye | **`wine` 同 prefix**；必要時隔離覆寫 | 誠實矩陣；禁排位宣稱 |
| Vanguard 等核心模式 | policy 拒絕或 UNKNOWN／FAIL | 禁宣稱通過 |

## 探測類別

| 反作弊 | 常見探測 | v3.0 策略 | 狀態 |
|--------|----------|-----------|------|
| EasyAntiCheat | 驅動簽章、核心回調 | strawwu_ipc 驅動 stub + 完整性回應 | FUNCTIONAL — ProbeEngine + bridge PolicySet，誠實 grade B/C（禁排位宣稱） |
| BattlEye | 核心掃描、DLL 完整性 | bridge syscall 攔截 + 假驅動介面 | FUNCTIONAL — 探測通過、不崩潰，誠實 grade B |
| Vanguard | TPM、啟動時核心載入 | microvm + TPM stub | FUNCTIONAL（受限）— TPM stub 就位，grade F（核心載入無法完整模擬） |
| 自訂 AC | 視窗/debugger 探測 | native 協作 + 偵測 API 回應；必要時 container 覆寫 | FUNCTIONAL — Window/Process/Debugger + bridge game profile |

## kernel 橋接（Phase 2 協同）

`strawwu_ipc` 核心模組提供：

- 假 `\\.\`-style 裝置節點
- IOCTL 回應表（可配置 per-profile）
- 不宣稱通過官方簽章驗證

## CI 矩陣

`tests/anticheat-matrix/run.sh` 產出：

```json
{
  "matrix_version": "1",
  "cases": [
    {"name": "eac_driver_probe", "backend": "native", "status": "FUNCTIONAL", "grade": "C", "notes": "ProbeEngine stateful multi-round"},
    {"name": "battleye_init", "backend": "native", "status": "FUNCTIONAL", "grade": "B", "notes": "syscall dispatch + DLL integrity"},
    {"name": "vanguard_tpm_probe", "backend": "microvm", "status": "FUNCTIONAL", "grade": "F", "notes": "TPM stub present, kernel-load limited"}
  ]
}
```

## Hub 顯示

compat-db 等級：A（可玩）/ B（可啟動）/ C（探測通過）/ F（崩潰）
