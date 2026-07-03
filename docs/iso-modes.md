# StrawWU ISO build modes

Three verification tiers — pick by speed vs fidelity. **Always run preflight before expensive verification.**

## Mode summary

| Mode | Speed | Builds ISO? | Squashfs | Boot-test | Use for |
|------|-------|-------------|----------|-----------|---------|
| **dev-vm** | Fastest | No | — | In-VM script | runtime, services, UI, proxy, config |
| **dev-iso** | Medium | Yes (zstd -l3) | Fast | BIOS only | live boot, casper, Plymouth, desktop defaults |
| **release-iso** | Slowest | Yes (xz) | Full | BIOS + UEFI | tags, GitHub Release, Phase gate, public test |

## Hard gate (all modes)

```
build / code change
  → preflight (integrity + feasibility)
  → PASS only then → verification (boot-test / dev-vm test / E2E)
```

- ISO paths: `make preflight-iso-before-boot` before any `boot-test-*`
- dev-vm: `make preflight-dev-vm` before `dev-vm-sync` / `dev-vm-test`
- Pipeline: `longtask_preflight_gate.sh` enforces this for Phase 2+

## 1. dev-vm (daily development)

No ISO. Use an installed StrawWU VM:

```bash
cp tests/dev-vm/vm.env.example tests/dev-vm/vm.env
# edit disk / SSH / sync paths

make dev-vm-sync      # rsync components → VM, restart services
make dev-vm-test      # run test command in VM
make dev-vm-cycle     # sync → test → rollback on FAIL
make dev-vm-rollback  # restore qemu snapshot
```

Good for: desktop, strawwu-runtime, Windows app proxy, systemd units, UI scripts — anything **after** install.

## 2. dev-iso (medium)

Fast live ISO for casper / Plymouth / pre-install checks:

```bash
make dev-iso
make boot-test-dev-iso   # preflight + BIOS-only QEMU (~15 min)
```

Squashfs:

```bash
mksquashfs … -comp zstd -Xcompression-level 3 -processors "$(nproc)" -e boot
```

- Does **not** skip squashfs (`SKIP_SQUASHFS=0`)
- Preflight relaxed on SHA256 / squashfs age (still checks marker, Plymouth, initrd modules)
- **Do not** use for Phase PASS or Release

## 3. release-iso (formal)

Official deliverable build:

```bash
make release-iso
make boot-test-release-iso   # preflight + BIOS + UEFI
```

Squashfs:

```bash
mksquashfs … -comp xz -b 1M -Xbcj x86 -processors "$(nproc)" -e boot
```

- Full preflight (strict)
- Phase 2 pipeline uses this mode
- Required before `mark PASS` / GitHub Release

## Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `STRAWWU_ISO_MODE` | `release-iso` | `dev-vm` \| `dev-iso` \| `release-iso` |
| `STRAWWU_BOOT_TEST_MODES` | mode-dependent | `bios` or `bios,uefi` |
| `STRAWWU_PREFLIGHT_STRICT` | `0` dev-iso / `1` release | Strict checksum & squashfs checks |
| `STRAWWU_SKIP_SQUASHFS` | `0` in pipeline | `1` only for local `make repack-iso` debug |

## Anti-patterns (do not)

- `make repack-iso` + boot-test in pipeline (skips squashfs → missing marker/branding)
- Parallel `build-iso` + `boot-test` on same ISO file
- `test-phase2` static PASS without `boot-result.json` top-level PASS
- Using dev-iso for Phase 2 formal acceptance
