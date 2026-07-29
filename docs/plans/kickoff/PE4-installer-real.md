# PE4 — Installer real

## Goal
EXE/MSI install path via native: unpack, app registry, shortcuts; open uses same path; no wine.

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
1. `tests/portable/output/pe-installer.json` top-level status acceptable per stage verify
2. bump + commit + push `main` when code changes
3. Wait for Hermes `trigger-verify` (do not self-declare final PASS)
