# NT4 — Anticheat Honest Matrix 階段報告

| 任務 | nt4-anticheat-honest |
|------|----------------------|
| Track | StrawNT 優玩 |
| 產品 | StrawNT |
| 版本 | 0.7.1.37 |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 目標

產出 EAC／BattlEye／Vanguard／CustomAC 探測矩陣，誠實 grade A/B/C/F（反作弊實際 cap ≤B；Vanguard=F），目標為可運行／不崩潰；**禁宣稱排位／官方簽章通過**。

## 交付物

| 類型 | 路徑 |
|------|------|
| 探測 crate | `components/strawwu-anticheat` |
| Probe PE fixtures | `components/strawwu-nt`（`build_win32_*_probe_pe`） |
| 驗證二進位 | `nt-anticheat-verify` |
| 煙測腳本 | `tests/strawnt/nt4-anticheat-honest.sh` |
| 驗收證據 | `tests/strawnt/output/nt4-anticheat.json` |

## 本階段 cases

- `eac_driver_probe` — EasyAntiCheat / native / PARTIAL + real surface-probe PE
- `battleye_init` — BattlEye / native / PARTIAL + real surface-probe PE
- `vanguard_tpm_probe` — Vanguard / microvm / PARTIAL + grade **F**（不宣稱真實 vendor PE）
- `custom_ac_window_process` — CustomAC / native / PARTIAL + real surface-probe PE

## 本地驗證結果

- 執行：`bash tests/strawnt/nt4-anticheat-honest.sh`
- 測試：`cargo test -p strawwu-anticheat`（30 passed）+ anticheat probe PE parse
- 證據：`tests/strawnt/output/nt4-anticheat.json` → `status=PARTIAL`（version=0.7.1.37），cases=4，real_pe=3，`ranked_pass_claimed=false`
- grades：B（EAC/BE/CustomAC）、F（Vanguard）

## 誠實邊界（known_limitations）

- StrawNT surface-probe PE + ProbeEngine + bridge PolicySet；**非** vendor EAC/BE/Vanguard 二進位
- 目標=不崩潰＋誠實等級；**不宣稱排位／官方 AC 簽章通過**
- Hub A（可玩）對反作弊強制禁止；Vanguard 維持 grade F
- 頂層 status 維持 **PARTIAL**（優玩禁止以 simulated／假 probe 當頂層 PASS）

## Hermes 驗收命令

```bash
test -f tests/strawnt/output/nt4-anticheat.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/strawnt/output/nt4-anticheat.json
jq -e '(.cases|length) >= 1 or (.results|length) >= 1' tests/strawnt/output/nt4-anticheat.json
jq -e '(.claims.ranked_pass_claimed // false) == false' tests/strawnt/output/nt4-anticheat.json
```

## 排除項（已遵守）

- 未改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session／StrawWU 工作區
- 未用 Wine／Proton 底層；`execution_backend=native`
- 未用 WinBox 命名；未宣稱完整 Windows 相容
