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

Built debs publish to the **strawwu-fork** APT suite:

```bash
make build-fork-packages
make publish-fork-debs
```

Output repo: `os-image/output/apt-fork-repo/` (`dists/strawwu-fork/`).  
Branding sources: `os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources`.

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
| `scripts/publish-fork-debs.sh` | Publish `output/*.deb` to strawwu-fork APT suite |
| `os-image/scripts/lib/fork-apt-env.sh` | Fork APT suite paths from registry + target JSON |

## Cleanroom policy

Do not copy legacy/archived package trees. Start from Ubuntu/Debian source or the
`_template/` scaffold and apply only the deltas required for StrawWU.
