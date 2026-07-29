# GX5-closeout

## Goal
See Hermes plan `/root/.hermes/plans/2026-07-29_strawwu-portable-game-compat.md` stage `GX5`.

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
