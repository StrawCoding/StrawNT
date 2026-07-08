# ~~Official~~ 已作廢 — 見 DEV-physical-blank-display.md

> **2026-07-08**：使用者未授權正式版；本任務書作廢。改走 `docs/plans/kickoff/DEV-physical-blank-display.md`。

## 範圍（作廢）
- 使用者回報：實體機用 StrawWU ISO / 開機 **無畫面**（黑屏）。
- ~~版本目標：`1.0.0.0`（official-release）。~~
- 須治本：實體機螢幕有正常開機顯示（品牌 Plymouth / 進度，不得長黑畫面），且不破壞既有 QEMU BIOS+UEFI boot-test / install E2E。

## PASS 條件
1. `STRAWWU_OFFICIAL_RELEASE=1 make preflight`（或專案等效 official preflight）exit 0
2. 必要時重打 `make release-iso`；`sha256sum -c` 對新 ISO PASS
3. `make boot-test-release-iso` → `tests/boot/output/boot-result.json` **頂層** `status=PASS`
4. 實體機驗證證據寫入本報告：開機螢幕有畫面（截圖或錄影路徑 + 機型 + BIOS/UEFI + 啟動媒體路徑）
5. 更新 `docs/plans/stage-reports/OFFICIAL-physical-blank-display-report.md`
6. 勿自行宣稱 official-release PASS；由 Hermes mark

## 禁止
- 複製 `封存/` legacy
- `SKIP_SQUASHFS=1` 當最終驗收
- 並行多條 build 寫同一 ISO
- Hermes/worker 自宣稱 PASS
- 只改檔名不改內容

## 證據路徑
- `tests/boot/output/boot-result.json`
- `tests/boot/output/serial-bios.log` / `serial-uefi.log`
- `os-image/output/StrawWU-1.0.0.0-amd64.iso`（或 bump 後新版）
- 本報告內實體機證據

## 關聯
- 進行中：`official-release`；QEMU install-e2e 可能仍在跑，以本 FAIL 優先直至實體畫面 PASS，再合併回 official closeout。
