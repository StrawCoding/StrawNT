# StrawWU Secure Boot MOK (Machine Owner Key)

This directory holds the **persistent** StrawWU Machine Owner Key used to sign the
custom StrawWU kernel so it boots under UEFI Secure Boot after the owner enrolls
the key once (via `shim`/MokManager).

## Files

| File | Tracked | Purpose |
|------|---------|---------|
| `StrawWU-MOK.key` | **NO** (gitignored) | RSA-2048 private signing key. **Secret.** |
| `StrawWU-MOK.crt` | yes | PEM certificate — used by `sbsign`/`sbverify` at build/preflight. |
| `StrawWU-MOK.cer` | yes | DER certificate — shipped to rootfs, used by `mokutil --import` for enrollment. |

## Key governance

- The private key is a **build secret**. It is never committed. On the trusted
  build host it persists at `StrawWU-MOK.key`; `generate-mok.sh` only creates a
  new pair when one is absent (stable signatures across releases → users enroll
  once).
- To build the custom kernel on a fresh host, provision the same
  `StrawWU-MOK.key` out-of-band (secret store) alongside the tracked public cert.
  Custom-kernel builds fail closed without it: the kernel image and every packaged
  module must be signed by the same MOK. The untouched Canonical Ubuntu kernel and
  initrd remain the no-MOK recovery path.
- The MOK is a self-owned key, **not** a trusted CA. Enrolling it only permits
  booting StrawWU-signed artifacts on the machine where the owner explicitly
  enrolled it.

## Regenerate (only if the key is lost / compromised)

```sh
os-image/scripts/secureboot-route/generate-mok.sh
```

Regenerating invalidates prior signatures; users would need to re-enroll the new
MOK. Avoid unless necessary.
