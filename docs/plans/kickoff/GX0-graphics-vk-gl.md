# GX0 — Graphics Vulkan / OpenGL

## Goal
Land DXGI/D3D11→Vulkan and wgl→GL/present bridging on the Portable **native** path with observable triangle/present evidence.

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawWU-portable`
- Branch: `main` only
- Plan: `/root/.hermes/plans/2026-07-29_strawwu-portable-game-compat.md`

## Allowed references (study only)
- ReactOS and Wine public docs/behavior may be studied.
- Do **not** link, depend on, invoke, install, or ship Wine/Proton.
- Specs: `components/specs/graphics-stack.md`

## Forbidden
- ISO / desktop / kernel workspaces
- Wine/Proton runtime
- WinBox naming
- Claiming full Windows / anti-cheat ranked pass

## PASS
1. `tests/portable/output/gx-graphics.json` top-level status `PASS` or `PARTIAL` (PARTIAL must list gaps)
2. bump + commit + push `main` when code changes
3. Wait for Hermes `trigger-verify` (do not self-declare final PASS)
