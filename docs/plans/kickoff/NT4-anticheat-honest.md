# NT4 — Anticheat Honest Matrix

| 任務 | nt4-anticheat-honest |
|------|----------------------|
| Track | StrawNT 優玩 |
| 產品 | StrawNT |
| 目標 | 產出 EAC／BattlEye／Vanguard（及可得案例）探測矩陣與 grade A/B/C/F；可運行／不崩潰；**禁宣稱排位／官方通過** |

## 交付

- `components/strawwu-anticheat`（ProbeEngine + bridge PolicySet）
- `components/strawwu-nt` anticheat surface-probe PE fixtures
- `nt-anticheat-verify` → `tests/strawnt/output/nt4-anticheat.json`
- `tests/strawnt/nt4-anticheat-honest.sh`

## 誠實邊界

- 反作弊實際 cap ≤B；Vanguard = **F**
- **禁止** `ranked_pass_claimed=true`／官方 AC 簽章通過／Hub A（可玩）
- 探測 PE 為 StrawNT surface probe，**不是** vendor EAC／BattlEye／Vanguard 二進位
- 禁止 Wine／Proton 底層

## 驗收（Hermes）

```bash
test -f tests/strawnt/output/nt4-anticheat.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/strawnt/output/nt4-anticheat.json
jq -e '(.cases|length) >= 1 or (.results|length) >= 1' tests/strawnt/output/nt4-anticheat.json
jq -e '(.claims.ranked_pass_claimed // false) == false' tests/strawnt/output/nt4-anticheat.json
```
