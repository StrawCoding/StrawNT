# ADR — StrawNT Wine Pivot（NTW0）

- **Status:** Accepted
- **Date:** 2026-08-07
- **Stage:** `ntw0-contract-legal`
- **Plan:** `/root/.hermes/plans/2026-08-07_151521-strawnt-wine-pivot.md`

## Context

StrawNT 先前以自研 **native PE** 為產品預設，並以硬契約「禁 Wine／Proton」約束文件與 verify。該路線無法在可交付時程內達成旗艦相容目標；2026-08-07 Plan Picker 已鎖定 **Wine pivot**。

## Decision

| 項目 | 鎖定值 |
|------|--------|
| `wine_ban_policy` | **lift_ban** — 廢止「禁 Wine／Proton」產品硬契約 |
| 預設 `execution_backend` | **wine** |
| 引擎 | **proton-ge**（vendored 全樹；大檔 **git-lfs**） |
| 誠實標示 | 狀態列／文件必須顯示 **powered by Wine** |
| 既有 native PE | **soft_reset** — 封存為 legacy／research；保留 git 歷史；勿刪歷史證據 |
| Hub | 既有 **Electron** `hub/`（不改走 StrawWine Vue HTTP GUI） |
| 宿主 | Linux x86_64 only |
| 誠實矩陣 | PASS／PARTIAL／FAIL／UNKNOWN（禁虛報） |

## Consequences

1. README／USER-GUIDE／產品路徑 verify **不得**再要求 `wine_proton_used=false` 或 native-only 作為 PASS。
2. native 路徑僅經 `STRAWNT_LEGACY_NATIVE=1`（unsupported）或 `tests/archive/native/`／歷史證據保留。
3. LGPL：每個 release 必須附 `docs/legal/WINE-LGPL.md`、`THIRD_PARTY_NOTICES` 與 source offer。
4. 引擎實際 vendor／runner 在 **NTW1**；本階 **禁止**下載完整 GE 大檔。
5. 禁宣稱完整 Windows／排位／官方反作弊通過。

## Soft-reset rules

- **Keep / adapt:** CLI、launcher、Hub、app-registry、packaging、versioning、matrix schemas。
- **Archive / deprecate:** 預設 native、`wine_proton_used=false` 產品硬閘、Game Compat「native-only」宣稱。
- **Do not delete:** `tests/**/output/*` 歷史 JSON、stage reports（標 legacy／歷史即可）。

## Related

- StrawWine 合併政策：`docs/decisions/2026-08-07-strawwine-merge.md`
- 法律：`docs/legal/WINE-LGPL.md`、根目錄 `THIRD_PARTY_NOTICES`
- 證據：`tests/strawnt/output/ntw0-contract.json`
