# StrawWU Portable Core packaging

Track **A+3** skeleton for a **cross-distro, self-contained Win-compat core**
(runtime / nt / launcher / graphics·audio / Hub / CLI).

This directory does **not** claim full Windows compatibility. It does **not**
use Wine/Proton as a substrate, and it does **not** introduce `WinBox` /
`winbox` naming or per-app sandbox defaults.

## Layout

| Path | Purpose | Stage |
|------|---------|-------|
| `prefix/` | Self-contained `$STRAWWU_PREFIX` (bundled libs + rpath) | pc1 |
| `appimage/` | AppImage (or equivalent single-dir bundle) recipes | pc2 |
| `flatpak/` | Flatpak manifest + notes (honest PARTIAL allowed) | pc3 |
| `../` (deb) | Existing Debian packaging — unchanged ISO/deb track | — |

## Inventory

Crate → artifact mapping lives in:

`docs/plans/portable-core/inventory.json`

Required core keys: `runtime`, `nt`, `launcher`, `cli`, `graphics`, `audio`, `hub`.

## Smoke

Scaffold stub (pc0):

```bash
bash tests/portable/smoke-prefix.sh --help
bash tests/portable/smoke-prefix.sh --dry-run
```

Full prefix build / `--version` / `status` without system `strawwu-*` debs is **pc1**.

## Explicit non-goals

- ISO / os-image / Plymouth / Calamares / kernel / desktop session changes
- Replacing the StrawWU Live USB / installed-distro track
- Declaring complete Windows application compatibility
