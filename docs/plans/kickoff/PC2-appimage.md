# Kickoff — pc2-appimage

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## 目標

產出可執行 **AppImage**（或等價單目錄／單檔 portable bundle），附 SHA256，
並在乾淨容器內煙測 CLI（`--version`／`status`）。

## 專案路徑

`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
分支：`portable-core-a3`

## 範圍

- `components/packaging/portable/build-appimage.sh` + `make portable-appimage`
- AppDir（`usr/bin/strawwu`、`usr/lib/strawwu/`）+ `.portable.tar.gz`；可選 Type-2 `.AppImage`
- `tests/portable/smoke-appimage.sh` → `tests/portable/output/smoke-appimage.json`
- `tests/portable/output/SHA256SUMS`
- bump + commit + push（本 stage 不 merge main）

## 禁止

- 改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- Wine／Proton 當底層、WinBox 命名、宣稱完整 Windows 相容
- 動主工作區 `/mnt/data/code/project/StrawCoding/StrawWU`

## PASS 條件

1. 產出可執行 AppImage 或等價 bundle（AppDir／portable.tar.gz）
2. `tests/portable/output/SHA256SUMS` 存在且可對產物驗證
3. 乾淨容器煙測：`AppRun --version` 與 `status` 成功
4. `tests/portable/output/smoke-appimage.json` 頂層 `status=PASS`
5. 版本已 bump；工作區乾淨已 push

## 驗證（僅 Hermes `trigger-verify`）

```bash
test -f tests/portable/output/smoke-appimage.json
jq -e '.status == "PASS"' tests/portable/output/smoke-appimage.json
test -f tests/portable/output/SHA256SUMS
```

Worker 完成後等 Hermes verify；勿自行宣稱最終 PASS。
