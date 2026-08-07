# Flatpak sandbox notes — org.strawcoding.strawnt (NTW7)

## Verdict

**PARTIAL.** Do not claim full Flatpak sandbox compatibility for PE execution
or Wine/Proton-GE prefixes. Primary shipping formats: **deb** / **rpm**.

## Why PARTIAL

1. **PE paths** — Launching host `.exe`/`.msi` needs arbitrary host paths;
   portal-only grants are insufficient.
2. **Wine prefix UX** — Prefixes under `~/.local/share/strawnt/` plus Z: drive
   mapping expect host-visible writable locations.
3. **Vendored GE** — Full Proton-GE tree is multi-GB (git-lfs); Flatpak bundling
   of the engine is deferred.
4. **finish-args hole** — Manifest includes `--filesystem=host` which weakens
   isolation on purpose; packaging stays PARTIAL.

## Explicit non-claims

- Not a silent rebrand of Wine as self-made PE (**powered by Wine** required)
- Not full Windows compatibility
- Not ranked / official anti-cheat pass
- Not full Flatpak sandbox isolation for PE/session
