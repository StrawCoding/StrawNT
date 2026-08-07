# StrawNT packaging (NTW7)

Delivery: **gui_local** · **desktop_mime** · **deb** · **rpm** · **flatpak (PARTIAL)**

> Product default: `execution_backend=wine` / `engine=proton-ge` · **powered by Wine**.
> Legal: `docs/legal/WINE-LGPL.md`, `THIRD_PARTY_NOTICES`.

## Layout

| Path | Purpose |
|------|---------|
| `desktop/` | `.desktop.in` templates (menu, MIME open, Hub gui_local) |
| `mime/strawnt-win32.xml` | shared-mime-info for `.exe`/`.msi` |
| `hub/strawnt-hub-entry.json` | Electron Hub track contract |
| `flatpak/` | Manifest stub + sandbox notes (**PARTIAL**) |
| `rpm/strawnt.spec.in` | RPM spec template |

Legacy OS-image helpers remain in `strawwu-branding/` / `strawwu-system/` /
`build-debs.sh` (not the NTW7 product release path).

## Build

```bash
bash scripts/build-release.sh
bash scripts/sign-release.sh
```

Artefacts land in `dist/` and repo-root `SHA256SUMS`.

Engine note: packages ship PIN + fetch SOP under `/usr/lib/strawnt/third_party/proton-ge/`.
Full GE dist (git-lfs) is **not** embedded in deb/rpm (~1.5G); install via
`scripts/fetch-proton-ge.sh` or bind-mount for CI smoke. Wrapper sets
`STRAWNT_ROOT=/usr/lib/strawnt`.

GUI note: deb/rpm **bundle** Electron under
`/usr/lib/strawnt/hub/electron-runtime/` so `strawnt-hub` starts after a normal
install (no separate `npm install`). gui_local smoke must observe a real X11
window (`xwininfo`), not only `--version`.

## Smoke

```bash
bash tests/strawnt/ntw7-packaging.sh
jq .status tests/strawnt/output/ntw7-packaging.json
```

## Explicit non-claims

- Not full Windows / ranked anti-cheat
- Flatpak not a full sandbox product path (honest PARTIAL)
- Not an OS/ISO/desktop distribution
