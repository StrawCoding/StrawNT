# DEV: 實體開機無畫面

## 範圍
- 使用者回報：實體機用 StrawWU ISO / 安裝後開機 **無畫面**（黑屏）。
- **非正式版**：`official-release` 已停止；VERSION 維持 `0.7.0.11`；勿 bump 至 `1.0.0.0`、勿建立 `.official-release-authorized`。
- 須治本：實體機螢幕有正常開機顯示（Plymouth / 進度，不得長黑畫面），且不破壞既有 QEMU BIOS+UEFI boot-test。

## PASS 條件
1. `make preflight` exit 0
2. `make dev-iso`（或必要時 `make release-iso`）後 `make boot-test-dev-iso` → `tests/boot/output/boot-result.json` **頂層** `status=PASS`
3. 實體機驗證證據寫入 `docs/plans/stage-reports/DEV-physical-blank-display-report.md`：開機螢幕有畫面（截圖或錄影路徑 + 機型 + BIOS/UEFI + 啟動媒體）
4. 勿自行宣稱 stage PASS；由 Hermes mark

## 禁止
- 複製 `封存/` legacy
- `SKIP_SQUASHFS=1` 當最終驗收
- 並行多條 build 寫同一 ISO
- 觸發 / 續跑 `official-release` 或 `1.0.0.0`
- Hermes/worker 自宣稱 PASS
- 只改檔名不改內容

## 證據路徑
- `tests/boot/output/boot-result.json`
- `tests/boot/output/serial-bios.log` / `serial-uefi.log`
- `os-image/output/StrawWU-*.iso`（dev-iso 或 release-iso，非 1.0.0.0 正式版）
- `docs/plans/stage-reports/DEV-physical-blank-display-report.md`

## 關聯
- stage：`post-hw-t1-live-usb`（實機 Live USB 矩陣）
- `official-release`：PENDING，待使用者明示授權後才可重啟
