# GX4 — Anticheat Matrix 階段報告

| 任務 | gx4-anticheat-matrix |
|------|----------------------|
| Track | Game Compat |
| 版本 | 0.7.1.31 |
| 日期 | 2026-07-29 |
| Worker | 階段 19/20 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

產出 EAC／BattlEye／Vanguard／自訂 AC 探測矩陣，誠實 grade A/B/C/F（反作弊實際 cap ≤B；Vanguard=F），目標為可運行／不崩潰；**禁宣稱排位／官方簽章通過**。

## 交付物

| 類型 | 路徑 |
|------|------|
| 探測 crate | `components/strawwu-anticheat` |
| 煙測腳本 | `tests/portable/smoke-gx-anticheat.sh` |
| 原始探針證據 | `tests/portable/output/gx4-anticheat-raw.json` |
| 驗收證據 | `tests/portable/output/gx-anticheat.json` |

## 本階段 cases

- `eac_driver_probe` — EasyAntiCheat / native / PARTIAL
- `battleye_init` — BattlEye / native / PARTIAL
- `vanguard_tpm_probe` — Vanguard / microvm / PARTIAL + grade **F**
- `custom_ac_window_process` — CustomAC / native / PARTIAL

## 本地驗證結果

- 執行：`bash tests/portable/smoke-gx-anticheat.sh`
- 測試：`cargo test -p strawwu-anticheat`（28 passed）
- 證據：`tests/portable/output/gx-anticheat.json` → `status=PARTIAL`（version=0.7.1.31），cases=4
- bridge 副作用：每案含 `strawwu-bridge` PolicySet seccomp profile 探測

## Hermes 驗收命令（由 Hermes runner 執行）

```bash
test -f tests/portable/output/gx-anticheat.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/gx-anticheat.json
jq -e '(.cases|length) >= 1 or (.results|length) >= 1' tests/portable/output/gx-anticheat.json
```

## 誠實邊界（known_limitations）

- ProbeEngine stub + bridge PolicySet；非真實 EAC/BE/Vanguard 二進位
- 目標=不崩潰＋誠實等級；**不宣稱排位／官方 AC 簽章通過**
- Hub A（可玩）對反作弊強制禁止；Vanguard 維持 grade F

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows 相容
