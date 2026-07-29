# PE0 — Remove Wine / restore native default

## Goal
Withdraw Wine/Proton shortcut from StrawWU-portable `0.7.1.17` and restore self-built PE / `execution_backend: native` as the only default path for install/open/run.

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawWU-portable`
- Branch: `main` only
- Plan: `/root/.hermes/plans/2026-07-29_130725-strawwu-portable-native-pe-real-exec.md`

## Allowed references (study only)
- Public ReactOS docs/source behavior may be studied as ABI/PE design reference.
- Public Wine docs/source behavior may be studied as ABI/PE design reference.
- Do **not** link, depend on, invoke, install, or ship Wine/Proton.

## In scope
- Remove wine backend code and install.sh Wine provisioning
- Default backend = native
- Evidence JSON: `tests/portable/output/pe0-remove-wine.json` top-level `status=PASS`
- bump-version, commit, push `main`

## Out of scope / forbidden
- StrawWU ISO / os-image / desktop / kernel / Plymouth / Calamares
- Wine/Proton as runtime
- WinBox naming
- Claiming full Windows compatibility

## PASS
1. `tests/portable/output/pe0-remove-wine.json` top-level `status=PASS`
2. No product-path wine launch dependency (`wine_backend`, `ensure_wine`, `STRAWWU_BACKEND=wine`, `backend=wine`)
3. `components/strawwu-launcher/src/wine_backend.rs` absent
4. Clean tree pushed to origin/main

## Note
Hermes will run `trigger-verify` later. Do not self-declare final PASS.
