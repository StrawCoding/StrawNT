# Self-contained prefix (pc1)

Produced by `make portable-prefix` (or
`components/packaging/portable/build-prefix.sh`).

```
$STRAWWU_PREFIX/
  bin/strawwu              # CLI (runtime/nt/launcher/cli/graphics linked in)
  bin/strawwu-env          # env helper (STRAWWU_PREFIX + local registry)
  lib/                     # bundled non-baseline .so + $ORIGIN rpath
  share/strawwu/
    portable-prefix.json   # build manifest
    wincompat/             # baseline (copied from wincompat deb sources)
  var/lib/strawwu/
    app-registry.json      # local registry (no system /var/lib required)
  share/doc/strawwu-portable/
```

## Usage

```bash
make portable-prefix
export STRAWWU_PREFIX="$PWD/components/packaging/portable/prefix"
"$STRAWWU_PREFIX/bin/strawwu" --version
STRAWWU_APP_REGISTRY="$STRAWWU_PREFIX/var/lib/strawwu/app-registry.json" \
  "$STRAWWU_PREFIX/bin/strawwu" status
```

Hub is optional (`STRAWWU_PORTABLE_WITH_HUB=1`). This prefix does **not**
depend on system `strawwu-*` deb packages. Host glibc/libgcc remain the ABI
baseline.

Built `bin/` and `lib/` artifacts are gitignored; rebuild from source.
