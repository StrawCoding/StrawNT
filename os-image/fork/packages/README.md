# Fork upstream package overlays

Versioned Debian source trees for forked Ubuntu packages. Each subdirectory is one
package with `debian/` metadata (and optional `upstream/` vendor tree).

## Layout

```
os-image/fork/packages/
├── packages.json          # registry (schema strawwu-fork-packages/v1)
├── _template/             # copy to start a new fork package
│   ├── PACKAGE.yaml
│   ├── debian/
│   └── build-package.sh
├── <pkgname>/             # one forked upstream package
│   ├── PACKAGE.yaml
│   ├── debian/
│   ├── upstream/          # optional — gitignored tarballs
│   └── build-package.sh
└── output/                # built .deb artifacts (gitignored)
```

Example future packages:

```
os-image/fork/packages/gnome-shell/
os-image/fork/packages/mutter/
```

## Workflow

1. Copy `_template/` to `<pkgname>/`.
2. Edit `PACKAGE.yaml`, `debian/control`, and `debian/changelog`.
3. Fetch upstream source (`apt source <pkg>` or vendor tarball into `upstream/`).
4. Register `<pkgname>` in `packages.json` → `packages` array.
5. Implement `build-package.sh` (typically `dpkg-buildpackage` or `debuild`).
6. Run `make build-fork-packages`.

Built debs publish to the **strawwu-fork** APT suite (fork-f5).

## Fork strategies

| Strategy | When to use |
|----------|-------------|
| `debian-source` | Full upstream Debian source with StrawWU patches |
| `quilt-patches` | Minimal debian/ + `debian/patches/` series |
| `session-overlay-ref` | Document-only; actual delta lives in strawwu-* debs (e.g. gnome-shell via strawwu-shell) |

## Scripts

| Script | Purpose |
|--------|---------|
| `os-image/scripts/build-fork-packages.sh` | Build all registered packages |
| `os-image/scripts/validate-fork-package.sh` | Static gate for one package dir |
| `os-image/scripts/lib/fork-packages-env.sh` | Paths from `ubuntu-base-target.json` |

## Cleanroom policy

Do not copy legacy/archived package trees. Start from Ubuntu/Debian source or the
`_template/` scaffold and apply only the deltas required for StrawWU.
