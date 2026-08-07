# Legacy／archive — native-only 硬閘盤點（NTW0 soft-reset）

產品預設已改 **wine／proton-ge**。下列路徑曾要求 `wine_proton_used=false` 或 native-only PASS；NTW0 起改為 **legacy／歷史證據**，不再作產品硬契約。

## 歷史證據（保留，勿刪）

| 區域 | 範例 |
|------|------|
| StrawNT youwan | `tests/strawnt/output/nt0-*.json` … `nt6-*.json` |
| Game Compat | `tests/portable/output/gx-*.json` |
| PE 軌道 | `tests/portable/output/pe-*.json`、`smoke-*.json` |
| Stage reports | `docs/plans/stage-reports/NT*`、`GX*`、`PE*`（歷史宣稱） |

## 已軟重置的產品閘（scripts／claims）

- `tests/strawnt/nt0-rebrand.sh` … `nt6-openable.sh` — 廢止「禁 Wine」產品 assert；標 legacy
- `tests/portable/smoke-gx-*.sh`、`gx-closeout.sh`、`pe-closeout.sh`、`smoke-pe-*.sh` — 同上
- launcher／desktop：`X-StrawNT-Backend=wine`；unit test 不再禁 wine 字串
- verify bins（`nt_*_verify`、`gx_*_verify`）：輸出可含 `path_role=legacy_native`；**不得**再當產品「禁 Wine」閘

## 產品新契約證據

- `tests/strawnt/output/ntw0-contract.json`
- ADR：`docs/decisions/2026-08-07-wine-pivot.md`
