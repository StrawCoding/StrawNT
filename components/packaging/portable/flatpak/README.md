# Flatpak (pc3)

Package the Portable Core CLI as **`org.strawwu.Core`**.

## Status: PARTIAL (by design)

Flatpak **sandbox isolation alone cannot host PE load + SubsystemSession** for
arbitrary host PE paths. The manifest therefore requests host filesystem (and
related sockets/devices). That is an honest **PARTIAL** packaging path — never
promote PARTIAL to PASS / “fully sandboxed Windows-compatible”.

| Capability | Under Flatpak |
|------------|---------------|
| `strawwu --version` / `status` | Expected to work |
| PE launch / SubsystemSession | Needs `--filesystem=host` (or explicit paths); not sandbox-pure |
| GPU ICD / Vulkan | May remain PARTIAL depending on host |
| Wine / Proton / WinBox | Explicitly out of scope |

See `SANDBOX-NOTES.md` for finish-args rationale and required host portals.

## Build

```bash
make portable-prefix          # if needed
make portable-flatpak
# or: bash components/packaging/portable/build-flatpak.sh
```

Requires `flatpak` + `flatpak-builder`. First build pulls Freedesktop Platform/Sdk
`24.08` from Flathub (user installation).

Artifacts (gitignored under `flatpak/.build`, `flatpak/repo`, `flatpak/staged`,
`flatpak/dist/`):

| Path | Role |
|------|------|
| `org.strawwu.Core.yaml` | Manifest (tracked) |
| `dist/org.strawwu.Core-<ver>.flatpak` | Single-file bundle |
| `repo/` | Local OSTree repo |

## Smoke

```bash
make test-portable-flatpak
jq .status tests/portable/output/smoke-flatpak.json   # PASS or PARTIAL
```

Evidence: `tests/portable/output/smoke-flatpak.json`.
