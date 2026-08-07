# Kickoff — pc3-flatpak

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## 目標

產出 **Flatpak manifest + build**（`org.strawwu.Core`），煙測結果 JSON，
並誠實標註 sandbox 對 PE／SubsystemSession 的限制（允許 **PARTIAL**）。

## 專案路徑

`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
分支：`portable-core-a3`

## 範圍

- `components/packaging/portable/flatpak/org.strawwu.Core.yaml`
- `components/packaging/portable/flatpak/SANDBOX-NOTES.md`（權限／host FS 說明）
- `components/packaging/portable/build-flatpak.sh` + `make portable-flatpak`
- `tests/portable/smoke-flatpak.sh` → `tests/portable/output/smoke-flatpak.json`
- bump + commit + push（本 stage 不 merge main）

## 禁止

- 改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- Wine／Proton 當底層、WinBox 命名、宣稱完整 Windows 相容
- **假裝完整 Flatpak sandbox 相容**（PE／session 需 host filesystem → PARTIAL）
- 動主工作區 `/mnt/data/code/project/StrawCoding/StrawWU`

## PASS 條件

1. Flatpak manifest 存在（`org.strawwu.Core.yaml` 或等價路徑）
2. Flatpak build 產出（`.flatpak` bundle 與／或 local repo 安裝）
3. `tests/portable/output/smoke-flatpak.json` 頂層 `status` 為 `PASS` **或** `PARTIAL`
4. 文件說明 PE／session 權限需求（`SANDBOX-NOTES.md`）
5. 版本已 bump；工作區乾淨已 push

## 驗證（僅 Hermes `trigger-verify`）

```bash
test -f tests/portable/output/smoke-flatpak.json
jq -e '.status == "PASS" or .status == "PARTIAL"' tests/portable/output/smoke-flatpak.json
test -f components/packaging/portable/flatpak/org.strawwu.Core.yaml \
  || test -f components/packaging/portable/flatpak/org.strawwu.Core.yml \
  || test -f components/packaging/portable/flatpak/manifest.yaml
```

Worker 完成後等 Hermes verify；勿自行宣稱最終 PASS。
