# NT6-openable-app

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## Goal
使用者能開啟 StrawNT：一鍵 install 後 CLI 可用、應用選單可啟動、舊 StrawWU/暫存 handler 不擋雙擊、`strawnt open` 真實 fixture 有副作用。

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawNT`
- Product: **StrawNT**
- Branch: `main` only
- Plan: Hermes long-task stage `nt6-openable-app`

## Scope
- Clear stale `strawwu-open.desktop` / broken `/tmp` TryExec on `integrate` + `install.sh`
- App-menu `strawnt.desktop` (Exec=status) + MIME `strawnt-open.desktop` (NoDisplay)
- PATH ensure (`~/.local/bin` + `~/.config/strawnt/env.sh`)
- Evidence: `tests/strawnt/output/nt6-openable.json` top-level `status=PASS`, `mode!=simulated`
- bump + commit + push + GitHub Release when artifacts ready

## Forbidden
- ISO / desktop / kernel / StrawWU OS workspace changes
- Wine/Proton substrate
- WinBox naming
- Simulated / fake probe as top-level PASS

## PASS
1. `tests/strawnt/output/nt6-openable.json` with `status=PASS`, `mode!=simulated`
2. Claims: `cli_available`, `desktop_exec_exists`, `stale_handler_cleared`
3. Side-effect file non-empty (`side_effects.open_log`)
4. bump + commit + push `main` + Release
5. Wait for Hermes `trigger-verify`
