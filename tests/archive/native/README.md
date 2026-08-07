# Legacy／archive — native-only 硬閘盤點（NTW0 soft-reset）

產品預設已改 **wine／proton-ge**（**powered by Wine**）。下列路徑曾要求 `wine_proton_used=false` 或 native-only PASS；NTW0 起改為 **legacy／歷史證據**，不再作產品硬契約。

## 歷史證據（保留，勿刪）

| 區域 | 範例 |
|------|------|
| StrawNT youwan | `tests/strawnt/output/nt0-*.json` … `nt6-*.json` |
| Game Compat | `tests/portable/output/gx-*.json` |
| PE 軌道 | `tests/portable/output/pe-*.json`、`smoke-*.json` |
| Stage reports | `docs/plans/stage-reports/NT*`、`GX*`、`PE*`（歷史宣稱） |
| Kickoff 任務書 | `docs/plans/kickoff/`（見該目錄 `README.md`；已標 retired） |
| Portable-core 決策 | `docs/plans/portable-core/A3-cross-distro-core.md`（歷史；已標 retired） |
| Components Phase 6 | `make -C components test-legacy-wincompat`（歷史；非產品 Wine 驗收） |

## 已軟重置的產品閘（scripts／claims）

- `tests/strawnt/nt0-rebrand.sh` … `nt6-openable.sh` — 廢止「禁 Wine」產品 assert；標 legacy
- `tests/portable/smoke-gx-*.sh`、`gx-closeout.sh`、`pe-closeout.sh`、`smoke-pe-*.sh` — 同上；腳本 exclusions 已改寫為 legacy + wine 產品預設（**歷史 output JSON** `pe-*.json`／`gx-*.json`／`nt*.json` 仍保留舊宣稱作 archive）
- 公開產品煙測（USER-GUIDE）：`smoke-prefix`／`smoke-appimage`／`smoke-flatpak`／`matrix`／`closeout` — 腳本與現行證據皆為 `execution_backend=wine`
- `tests/portable/smoke-pe-real-exec.sh`、`tests/strawnt/nt3-real-launchers.sh` — **不再**因產品樹出現 Wine marker 而 `write_fail`
- Makefile：**產品目標**僅 `test-strawnt-ntw0-contract`；native-era 改名為 `test-legacy-portable-pe-*`／`test-legacy-portable-gx-*`／`test-legacy-strawnt-nt*`（含 nt3／nt6；help 獨立 Legacy 區）
- 根 `test-wincompat`：**LEGACY 別名** → `components test-legacy-wincompat`（不再宣稱一般 Phase 6 Windows 產品驗收）
- `components/Makefile`：`test-legacy-wincompat`（`test-wincompat` 僅相容別名）— **非**完整 Windows／產品 Wine 預設驗收
- `components/tests/wincompat/golden-apps.json` — 現行 `backend_default=wine`
- `tests/strawnt/nt6-openable.sh` — `path_role=legacy_native`；**不再**因 menu/open 出現 Wine 字樣而 `write_fail`
- `tests/strawnt/nt3-real-launchers.sh` — **不再**掃描產品樹 Wine marker 並 `write_fail`
- launcher／desktop：`X-StrawNT-Backend=wine`；open／install 預設 wine；unit test 允許 wine
- runtime：`ExecutionBackend::Wine` 為產品預設；native 為 legacy
- verify bins（`nt_*_verify`、`gx_*_verify`）：輸出可含 `path_role=legacy_native`；**不得**再當產品「禁 Wine」閘
- 現行規格：`components/README.md`、`components/specs/execution-backends.md` — 預設 wine；禁靜默改名

## 產品新契約證據

- `tests/strawnt/output/ntw0-contract.json`
- ADR：`docs/decisions/2026-08-07-wine-pivot.md`
- StrawWine 合併 C：`docs/decisions/2026-08-07-strawwine-merge.md`
- 法律：`docs/legal/WINE-LGPL.md`、`THIRD_PARTY_NOTICES`
