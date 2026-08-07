# ADR — StrawWine → StrawNT 合併政策 C（NTW0）

- **Status:** Accepted
- **Date:** 2026-08-07
- **Stage:** `ntw0-contract-legal`
- **Locked choice:** **C merge**（`strawwine_policy=merge_c`）

## Context

StrawWine（`/mnt/data/code/project/StrawCoding/straw-wine`）已是 system-Wine 產品殼（prefix／MIME／recipes／誠實矩陣）。StrawNT Wine pivot 後若雙旗艦並存，會造成引擎／MIME／行銷衝突。Plan Picker 鎖定 **C：合併進 StrawNT**。

## Decision — Policy C

吸收 StrawWine 的**殼層模式**進 StrawNT；旗艦引擎為 **vendored Proton-GE**；可保留 `backend=system-wine` 風味，但 **不再**把 StrawWine 當競爭旗艦。

### 合併邊界表

| 區塊 | 來源（straw-wine） | 落入 StrawNT | 備註 |
|------|-------------------|--------------|------|
| 產品殼／CLI 模式 | prefix create／list／run／open | `components/strawnt-engine/` + 既有 CLI | NTW2 起移植概念，非盲目複製 |
| MIME／桌面整合 | `.desktop`、選擇器、honest backend 標籤 | 既有 Electron Hub + launcher MIME | 預設改 wine／GE；選擇器可保留 system-wine vs GE |
| Recipes | vcrun、corefonts、crypt32、dxvk 等 | app-registry／engine recipes | LINE／Steam 種子在 NTW2 |
| 誠實矩陣 JSON | PASS／PARTIAL／FAIL／UNKNOWN | `tests/` schemas | 精神不變；backend 欄位改 wine |
| GUI | StrawWine Vue HTTP GUI | **不**作為主殼 | Hub 鎖定既有 **Electron** `hub/` |
| 引擎 | system Wine／可選 Proton | **GE-vendored** 為旗艦 | system-wine 僅風味／fallback |
| 品牌 | StrawWine 旗艦行銷 | 停止競爭旗艦 | 合併後以 StrawNT 對外 |
| StrawWinBox | — | **不變** | 自研 runtime 研究；仍禁偷換為 Wine |

### 產品定位（合併後）

| 產品 | 執行後端 | 定位 |
|------|----------|------|
| **StrawNT** | wine／**proton-ge**（旗艦）＋可選 system-wine | 旗艦：vendored GE + App Manager + Win32 IPC + Electron Hub |
| **StrawWine** | （合併／吸收） | 殼／recipe／矩陣模式併入 StrawNT；停止獨立旗艦 |
| **StrawWinBox** | 自研 NT runtime | 長期研究；禁 Wine 偽裝 |

## Follow-ups（非本階阻擋）

1. 在 straw-wine 倉庫更新 `docs/PRODUCT-BOUNDARY.md` 交叉連結（標「merged into StrawNT / policy C」）。
2. MIME 並裝：StrawNT 預設 wine／GE；若偵測舊 StrawWine handler，明示選擇器（禁靜默搶關聯）。
3. Prefix 目錄：StrawNT 用 `~/.local/share/strawnt/`；遷移策略在 NTW2+ 文件化。

## Non-goals

- 不把 StrawWine Vue GUI 換成主 Hub。
- 不刪除 straw-wine git 歷史。
- 不在本階（NTW0）搬運完整 recipe／引擎實作。

## Evidence

- `tests/strawnt/output/ntw0-contract.json` → `strawwine_policy=merge_c`、`hub=electron`
