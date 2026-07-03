# StrawWU Custom Kernel

Phase 2 deliverable: build `linux-image-strawwu` .deb from Ubuntu noble kernel source + `strawwu_ipc` module.

## Build

```bash
make -C kernel build          # 20-60 min; needs root for apt source fetch
export STRAWWU_KERNEL_DEB=$(ls kernel/output/linux-image-strawwu_*.deb | head -1)
make swap-kernel build-iso boot-test-iso
make test-phase2
```

## Module

`strawwu_ipc` — misc char device `/dev/strawwu_ipc` for Phase 6 device-proxy / anticheat IOCTL stubs.

## Status

Phase 2 — `linux-image-strawwu` .deb + `strawwu_ipc` module; use `make swap-kernel` to install into cloned rootfs.
