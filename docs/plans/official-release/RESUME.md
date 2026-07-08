# Official Release Resume State
# Generated: 2026-07-08T17:15+08:00
# Stage: official-release (8/8)

## Completed
- [x] .official-release-authorized (restored 2026-07-08)
- [x] VERSION=1.0.0.0
- [x] STRAWWU_OFFICIAL_RELEASE=1 make preflight → PREFLIGHT_EXIT=0
- [x] make build-iso → BUILD_ISO_EXIT=0
- [x] ISO: os-image/output/StrawWU-1.0.0.0-amd64.iso (4.8G)
- [x] sha256sum: 6e272f6d8ce9306c70a2712f87f0deb0c9fc6ffb48153540da03dc88e41ed691
- [x] SHA256SUMS (repo root + os-image/output)
- [x] DoD / HTML / validate / preflight gate scripts
- [x] version_policy.py (MAJOR>=1 with auth marker)
- [ ] make test-install-e2e — first run Terminated mid-bootloader (~93m); restarting

## Resume commands
```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
# ensure auth + version
test -f .official-release-authorized && cat VERSION  # expect 1.0.0.0
rm -f tests/install-e2e/output/.install-e2e.lock
nohup bash -c 'STRAWWU_OFFICIAL_RELEASE=1 VERSION=1.0.0.0 make test-install-e2e > /tmp/test-install-e2e-1.0.0.0-rerun.log 2>&1; echo E2E_EXIT=$? >> /tmp/test-install-e2e-1.0.0.0-rerun.log' >/dev/null 2>&1 &
# after E2E:
sha256sum -c SHA256SUMS
STRAWWU_OFFICIAL_RELEASE=1 make test-official-release
```

## Evidence notes
- Prior live-install reached e2e-bootloader-setup after rsync (tick 517)
- Worker VERSION was reverted to 0.7.0.11 mid-session; restored to 1.0.0.0
- .official-release-authorized was deleted (git D); restored
