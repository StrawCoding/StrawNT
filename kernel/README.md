# StrawWU Custom Kernel

Phase 2 deliverable: build `linux-image-strawwu` .deb from Ubuntu noble kernel source + StrawWU patches.

## Reference (do not reinvent)

- Ubuntu noble kernel: `apt source linux-image-$(uname -r)`
- Package: `linux-image-strawwu_<version>_amd64.deb`
- Install via: `STRAWWU_KERNEL_DEB=/path/to.deb make swap-kernel`

## Status

Not started — Phase 1 uses Ubuntu `linux-image-generic` to validate clone pipeline.
