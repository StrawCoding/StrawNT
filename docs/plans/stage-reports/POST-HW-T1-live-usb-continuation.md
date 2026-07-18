# POST-HW-T1 continuation state (worker resume)

| key | value |
|-----|-------|
| stage | post-hw-t1-live-usb |
| version | 0.7.1.7 |
| updated | 2026-07-19T07:45+08:00 |
| hermes_status | 0.7.1.6 實機仍黑 → 治本 `plymouth.ignore-serial-consoles`；待刷 0.7.1.7 |
| release_iso | ✅ `StrawWU-0.7.1.7-amd64.iso` SHA256 `cb4ad00a…` |
| boot_test | ✅ bios/uefi/secureboot PASS |
| matrix_iso | ✅ 0.7.1.7 T1 gate refreshed（QEMU proxy；實機待確認） |
| next_worker | 建議 Hermes `trigger-verify`；**請使用者刷 0.7.1.7** |

## Root cause (confirmed)

`console=ttyS0` for QEMU markers → Plymouth binds serial seat → **physical panel black**.  
QEMU `-display none` + serial markers hid the failure across multiple “fixes” including 0.7.1.6 generic default.

## Done this session

- GRUB / build-iso / secureboot-fallback: `plymouth.ignore-serial-consoles`
- live sanitize: DeviceTimeout=30 + shell theme CSS path + casper FLAVOUR
- preflight gate ttyS0 ↔ ignore-serial
- gtk-theme deb installs gnome-shell theme path
- VERSION 0.7.1.7 ISO；iso-before-boot PASS；boot-test 三模式 PASS；T1 preflight PASS

## Blockers

- Physical re-flash of **0.7.1.7** (worker has no panel) — 實機證據前禁止 mark PASS
