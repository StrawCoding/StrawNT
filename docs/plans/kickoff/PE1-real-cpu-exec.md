# PE1 — Real CPU exec

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## Goal
Native path executes a minimal console PE fixture with observable side effects (stdout or file write). Simulated success path is forbidden.

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawWU-portable`
- Branch: `main` only
- Plan: `/root/.hermes/plans/2026-07-29_130725-strawwu-portable-native-pe-real-exec.md`

## Allowed references (study only)
- ReactOS and Wine public docs/behavior may be studied.
- Do **not** link, depend on, invoke, install, or ship Wine/Proton.

## Forbidden
- ISO / desktop / kernel workspaces
- Wine/Proton runtime
- WinBox naming
- Claiming full Windows / anti-cheat compatibility

## PASS
1. `tests/portable/output/pe-real-exec.json` top-level status acceptable per stage verify
2. bump + commit + push `main` when code changes
3. Wait for Hermes `trigger-verify` (do not self-declare final PASS)
