# NT6-openable-app

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
