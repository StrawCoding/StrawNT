# GX2-light-2d3d

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## Goal
See Hermes plan `/root/.hermes/plans/2026-07-29_strawwu-portable-game-compat.md` stage `GX2`.

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawWU-portable`
- Branch: `main` only
- Plan: `/root/.hermes/plans/2026-07-29_strawwu-portable-game-compat.md`

## Allowed references (study only)
- ReactOS and Wine public docs/behavior may be studied.
- Do **not** link, depend on, invoke, install, or ship Wine/Proton.
- Specs in `components/specs/` (graphics-stack, anticheat-compat, runtime-cooperation, golden-apps-launch).

## Forbidden
- ISO / desktop / kernel workspaces
- Wine/Proton runtime
- WinBox naming
- Claiming full Windows / anti-cheat ranked pass / 3A complete

## PASS
1. Evidence JSON under `tests/portable/output/` per stage verify_commands
2. bump + commit + push `main` when code changes
3. Wait for Hermes `trigger-verify` (do not self-declare final PASS)
