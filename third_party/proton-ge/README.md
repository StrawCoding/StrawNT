# Vendored Proton-GE (StrawNT engine)

StrawNT flagship engine is **Proton-GE** (Wine family). Product honesty:

- `execution_backend=wine`
- `engine=proton-ge@<tag from PIN>`
- always **powered by Wine**
- do **not** claim all games / ranked anti-cheat / full Windows

## Layout

| Path | Role |
|------|------|
| `PIN` | Deterministic pin (tag, URLs, sha512) |
| `cache/*.tar.gz` | Upstream release archive (**git-lfs**) |
| `dist/` | Extracted tree (`files/bin/wine`, …) — rebuild via fetch; not committed |
| `README.md` | This SOP |

## git-lfs strategy

1. Large blobs live under `cache/` and are tracked by **git-lfs** (see root `.gitattributes`).
2. `dist/` is **extracted locally** from the LFS (or freshly downloaded) tarball — regenerable, gitignored.
3. Fresh clone: `git lfs pull` then `bash scripts/fetch-proton-ge.sh` (uses cache if present; otherwise downloads and verifies sha512).
4. Do not rely on CDN-only at runtime without a pin; PIN + checksum is the source of truth.

## Fetch / update SOP

```bash
# Install / refresh pinned release into cache/ + dist/
bash scripts/fetch-proton-ge.sh

# Verify pin + LFS attrs + wine binary
bash scripts/verify-proton-ge.sh
```

### Bump pin to a newer GE-Proton

1. Pick a release tag from https://github.com/GloriousEggroll/proton-ge-custom/releases
2. Update `PIN` (`tag`, URLs, `sha512`, `pinned_date`)
3. `bash scripts/fetch-proton-ge.sh`
4. `bash scripts/verify-proton-ge.sh`
5. Smoke: `bash tests/strawnt/ntw1-engine.sh`
6. `bash scripts/bump-version.sh` → commit + push `main`

## CLI

```bash
strawnt engine status   # pin + paths
strawnt doctor          # engine health (wine present, pin, honesty)
```

## License

Wine / Proton components are **LGPL** (and other upstream notices). See `docs/legal/WINE-LGPL.md` and root `THIRD_PARTY_NOTICES`. Source offer: upstream release URL in `PIN`.
