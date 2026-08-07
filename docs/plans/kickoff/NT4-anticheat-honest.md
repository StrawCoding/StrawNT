# NT4 — Anticheat Honest Matrix

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 優玩軌道任務書。「禁止 Wine／Proton 底層」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge；仍禁宣稱排位／官方 AC 通過。見 `docs/decisions/2026-08-07-wine-pivot.md`、`tests/archive/native/README.md`。

| 任務 | nt4-anticheat-honest |
|------|----------------------|
| Track | StrawNT 優玩（歷史） |
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
- ~~禁止 Wine／Proton 底層~~ → **已廢止（NTW0 lift_ban）**；本階證據仍為 native-era 歷史矩陣

## 驗收（Hermes）

```bash
test -f tests/strawnt/output/nt4-anticheat.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/strawnt/output/nt4-anticheat.json
jq -e '(.cases|length) >= 1 or (.results|length) >= 1' tests/strawnt/output/nt4-anticheat.json
jq -e '(.claims.ranked_pass_claimed // false) == false' tests/strawnt/output/nt4-anticheat.json
```
