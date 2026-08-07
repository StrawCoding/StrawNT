# Kickoff — pc5-closeout

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## 目標

Portable Core A+3 **收尾**：使用者文件、產物索引、SHA256、version bump、
將 `portable-core-a3` 合併並 push `main`、產出 closeout 證據 JSON（含 HTML 交付）。

## 專案路徑

`/mnt/data/code/project/StrawCoding/StrawWU-portable`  
分支：`portable-core-a3` → 合併 `main`

## 範圍

- 使用者文件：`docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md`
- 產物索引：`docs/plans/portable-core/artifacts.json` + `tests/portable/output/SHA256SUMS`
- Closeout 報告／HTML：`docs/plans/portable-core/closeout-report.md` + `html/`
- 證據：`tests/portable/output/closeout.json` 頂層 `status=PASS`
- bump + commit + push 分支；**FF merge／push `main`**
- 勿動主工作區 ISO／T1（`/mnt/data/code/project/StrawCoding/StrawWU`）

## 禁止

- 改 ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- Wine／Proton 當底層、WinBox 命名、宣稱完整 Windows 相容
- 把 Flatpak PARTIAL 改寫成 PASS
- 動主工作區未提交 ISO／T1 改動

## PASS 條件

1. `tests/portable/output/closeout.json` 存在且頂層 `status=PASS`
2. 產物索引與 SHA256 齊；pc0–pc4 證據仍可追溯
3. `portable-core-a3` 已合併進 `origin/main`（fast-forward）
4. 版本已 bump；工作區乾淨已 push

## 驗證（僅 Hermes `trigger-verify`）

```bash
test -f tests/portable/output/closeout.json
jq -e '.status == "PASS"' tests/portable/output/closeout.json
```

Worker 完成後等 Hermes verify；勿自行宣稱最終 PASS。
