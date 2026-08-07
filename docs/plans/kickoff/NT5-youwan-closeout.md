# NT5-youwan-closeout

> **歷史／retired（2026-08-07 Wine pivot／NTW0）：** 本 kickoff 為 native-era 任務書。其中「禁 Wine／Proton／Do not … Wine」為**歷史硬契約**，已廢止。現行產品預設 wine／proton-ge（powered by Wine）。見 `docs/plans/kickoff/README.md`、`docs/decisions/2026-08-07-wine-pivot.md`。

## Goal
See Hermes plan `/root/.hermes/plans/2026-07-29_strawnt-rebrand-youwan.md` stage `nt5-youwan-closeout`.

## Project
- Path: `/mnt/data/code/project/StrawCoding/StrawNT`
- Product: **StrawNT**
- Branch: `main` only
- Plan: `/root/.hermes/plans/2026-07-29_strawnt-rebrand-youwan.md`

## Scope
- User docs + honest boundaries (README / USER-GUIDE / user guide)
- Release artifacts (`StrawNT-*-x86_64.AppImage` / `.portable.tar.gz`) + SHA256
- Necessary cross-distro smoke (`tests/portable/output/matrix.json`, ≥3 distros)
- HTML closeout report
- Evidence: `tests/strawnt/output/nt5-closeout.json` top-level `status=PASS`, `product=StrawNT`
- bump + commit + push + GitHub Release (tag = `v` + VERSION)

## Allowed references (study only)
- ReactOS and Wine public docs/behavior may be studied.
- Do **not** link, depend on, invoke, install, or ship Wine/Proton.

## Forbidden
- ISO / desktop / kernel / StrawWU OS workspace changes
- Wine/Proton runtime substrate
- WinBox naming
- Claiming full Windows compatibility / anti-cheat ranked pass / 3A complete
- Simulated / fake probe as top-level PASS for youwan stages

## PASS
1. Evidence JSON under `tests/strawnt/output/nt5-closeout.json` with `status=PASS` and `product=StrawNT`
2. Prior stages nt0–nt4 evidence present and acceptable (nt3/nt4 may be honest PARTIAL)
3. bump + commit + push `main` + GitHub Release when artifacts ready
4. Wait for Hermes `trigger-verify` (do not self-declare final PASS)
