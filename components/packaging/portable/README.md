# StrawNT packaging

Cross-distro, self-contained **Wine／Proton-GE** Windows app runtime
(CLI / launcher / Hub / prefix／AppImage／Flatpak).

> **2026-08-07 Wine pivot：** 產品預設 `execution_backend=wine`／`engine=proton-ge`
>（**powered by Wine**）。舊「不使用 Wine／Proton」契約已廢止。

This directory does **not** claim full Windows compatibility. It does **not**
introduce `WinBox` / `winbox` naming or per-app sandbox defaults. StrawNT is an
independent product — not an OS / ISO / desktop distribution. Legal:
`docs/legal/WINE-LGPL.md`、`THIRD_PARTY_NOTICES`.

## Layout

| Path | Purpose | Stage |
|------|---------|-------|
| `prefix/` | Self-contained `$STRAWNT_PREFIX` (bundled libs + rpath) | pc1 |
| `appimage/` | AppImage (or equivalent single-dir bundle) recipes | pc2 |
| `flatpak/` | Flatpak manifest + notes (honest PARTIAL allowed) | pc3 |

## Build

```bash
make portable-prefix
make portable-appimage
make portable-flatpak
```

Optional Hub bundling: `STRAWNT_PORTABLE_WITH_HUB=1 make portable-prefix`.

Primary CLI binary: **`strawnt`** (`bin/strawwu` is a deprecated compat alias).

## Smoke

```bash
make test-portable-prefix
jq .status tests/portable/output/smoke-prefix.json
```

User guide: `docs/plans/portable-core/USER-GUIDE.md`

## Explicit non-goals

- ISO / os-image / Plymouth / Calamares / kernel / desktop session changes
- Declaring complete Windows application compatibility
- Declaring full Flatpak sandbox compatibility for PE / SubsystemSession
- Wine / Proton as execution substrate
