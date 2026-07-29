# Flatpak sandbox notes — org.strawwu.Core (pc3)

## Verdict

**PARTIAL.** Do not claim full Flatpak sandbox compatibility for PE execution
or SubsystemSession. Do not claim full Windows application compatibility.

## Why PARTIAL

1. **PE paths** — Launching host PE binaries requires reading arbitrary host
   paths. Default Flatpak home-only / portal-only grants are insufficient.
2. **SubsystemSession** — Shared Win32-style state (process graph, registry
   helpers, shared filesystem view) expects host-visible writable locations
   beyond `~/.var/app/org.strawwu.Core/`.
3. **Device / GPU** — Graphics bridge may need host DRI/Vulkan ICDs; access is
   environment-dependent even with `--device=dri`.
4. **finish-args hole** — The manifest includes `--filesystem=host` so CLI PE
   dispatch can see host files. That **weakens** sandbox isolation on purpose;
   packaging remains PARTIAL, not “secure full sandbox”.

## finish-args (manifest)

| Arg | Reason |
|-----|--------|
| `--filesystem=host` | Required for PE / session host path visibility (**PARTIAL**) |
| `--filesystem=home` | User data / registry helpers under `$HOME` |
| `--filesystem=xdg-download` | Common PE download location |
| `--device=dri` | Graphics bridge / present path |
| `--socket=wayland` / `fallback-x11` | GUI present when used |
| `--socket=pulseaudio` | Audio bridge when used |
| `--share=network` | Optional remote lookups |
| portal talk-names | Documented; **not sufficient alone** for PE |

## Required host visibility (summary)

For PE / SubsystemSession workloads, operators must allow at least:

- Host filesystem (manifest default: `--filesystem=host`), **or**
- Explicit path grants covering PE binaries + session data directories

Portals alone are **not** enough for arbitrary PE launch.

## What still works without pretending

- Packaging the self-contained CLI into Flatpak (`--version`, `status`)
- Cross-distro distribution of the core binary + bundled libs
- Documented, honest PARTIAL status in smoke evidence JSON

## Explicit non-claims

- Not a Wine/Proton substrate
- No `WinBox` / `winbox` naming
- Not full Windows compatibility
- Not full Flatpak sandbox isolation for PE/session
