# W8-S4 initramfs-hooks 階段報告

| 任務 | w8-s4-initramfs-hooks |
|------|-----------------------|
| 版本 | 0.5.0.7 |
| 日期 | 2026-07-06 |
| Worker | 階段 45/47（w8-s4-initramfs-hooks） |
| 最後驗證 | 2026-07-06T03:50 UTC-4（worker 階段 45/47 複驗） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

strawwu-initramfs-hooks deb — 安裝後目標系統 initramfs-tools：剝除 casper/live-boot live-media hook、強制 `BOOT=local` 磁碟開機；與 ISO initrd splice（strawwu-live-init / strawwu-live-bottom）互補。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-initramfs-hooks/` |
| CLI + core | `usr/bin/strawwu-initramfs-hooks`、`usr/lib/strawwu-initramfs-hooks/core.py` |
| 清單 | `usr/share/strawwu/initramfs-hooks/initramfs-hooks-manifest.yaml` |
| disk-boot conf | `etc/initramfs-tools/conf.d/strawwu-disk-boot` |
| baseline | `docs/plans/baselines/initramfs-hooks-baseline.json` |
| Preflight | `tests/preflight/test-initramfs-hooks.sh` |
| Makefile | `test-initramfs-hooks`；`preflight` 串接 |
| target-manifest | `strawwu-initramfs-hooks` 置於 `strawwu-target-identity` 之前 |
| chroot staging | `chroot-install-target-setup.sh` `stage_debs` 含本 deb |
| ISO | `os-image/output/StrawWU-0.5.0.7-amd64.iso`（自 0.5.0.6 複製；本階段不改 live initrd） |
| VERSION | `0.5.0.7` |

## 技術摘要

| 項目 | 說明 |
|------|------|
| 策略 | ISO 仍靠 initrd-splice 注入 strawwu-live-init/bottom；安裝後由 deb 剝除 casper/live-boot initramfs-tools hook |
| strip | 移除 `hooks/casper`、`hooks/live-boot`、`scripts/casper*`、`scripts/live*`、casper conf.d |
| disk boot | 安裝 `conf.d/strawwu-disk-boot`（`BOOT=local`）；同步 `initramfs.conf` |
| Calamares 時序 | target_setup 安裝本 deb → target_identity 執行 `update-initramfs` 重生磁碟 initrd |
| lifecycle | `lifecycle.initramfs_hooks` via strawwu-initd |
| postinst | `apply --skip-initramfs`（strip + conf；initramfs 重生留給 target-identity） |

## 驗收命令輸出（2026-07-06T03:50 UTC-4，worker 階段 45/47 複驗）

### `make test-initramfs-hooks` — exit 0

```
=== W8-S4 initramfs-hooks preflight ===
PASS: plan strawwu-initrd-plan.md
PASS: W8-S4 kickoff
PASS: initramfs-hooks package name
PASS: Depends strawwu-initd
PASS: initramfs-hooks-manifest schema v1
PASS: manifest lists casper + live-boot hooks to strip
PASS: disk-boot conf.d sets BOOT=local
PASS: core implements strip + disk-boot
PASS: initrd-splice retains ISO live-init/bottom (complement)
PASS: target-manifest includes strawwu-initramfs-hooks
PASS: initramfs-hooks staged before target-identity
PASS: chroot-install stages strawwu-initramfs-hooks deb
PASS: initramfs-hooks unit tests
PASS: strawwu-initramfs-hooks build-deb.sh succeeded
PASS: initramfs-hooks deb artifact strawwu-initramfs-hooks_0.5.0.7_all.deb
PASS: deb contains strawwu-disk-boot conf.d
PASS: deb contains strawwu-initramfs-hooks CLI
PASS: deb contains initramfs-hooks manifest
PASS: deb does not ship casper hook (strip-only)
=== W8-S4 initramfs-hooks done: PASS ===
```

Log: `/tmp/w8-s4-test-initramfs-hooks.log`

### `make preflight-iso-before-boot`（release-iso）— exit 0

```
=== StrawWU ISO preflight (before boot-test) mode=release-iso strict=1 ===
PASS: build-iso marker exists
PASS: swap-kernel marker exists
PASS: swap-kernel references strawwu
PASS: ISO file exists
PASS: ISO size 5596526592 bytes (>= 5GB)
PASS: SHA256SUMS validates
PASS: casper vmlinuz exists
PASS: casper initrd exists
PASS: casper minimal.squashfs exists
PASS: casper vmlinuz matches rootfs strawwu kernel image
PASS: initrd size 68955904 bytes (30M–250M)
PASS: initrd structure verify (initrd-splice)
PASS: initrd early3 has strawwu modules
PASS: initrd early3 has ISO filesystem module
PASS: minimal.squashfs 1541615616 bytes (>= 1000000000 branded, mode=release-iso)
PASS: minimal.squashfs mtime recent (0d old)
PASS: squashfs contains strawwu-boot-marker.service
PASS: squashfs contains strawwu-boot Plymouth theme
PASS: production squashfs has no install-e2e guest runner
PASS: GDM live autologin configured for ubuntu
PASS: GRUB has console=tty0 (physical display)
PASS: GRUB has username=ubuntu (casper live user)
PASS: build mode matches preflight (release-iso)
PASS: STRAWWU_SKIP_SQUASHFS=0 (full squashfs build)
PASS: no stray QEMU StrawWU processes
=== ISO preflight done ===
```

Log: `/tmp/w8-s4-preflight-iso-verify.log`

## 變更檔案

- `os-image/debs/strawwu-initramfs-hooks/`（新增 deb 套件）
- `os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml`
- `os-image/debs/strawwu-target-setup/tests/test-target-setup.py`
- `os-image/scripts/chroot-install-target-setup.sh`（build + stage + chroot 驗證）
- `docs/plans/baselines/initramfs-hooks-baseline.json`（新增）
- `tests/preflight/test-initramfs-hooks.sh`（新增；含 chroot staging 檢查）
- `Makefile`（`test-initramfs-hooks`、preflight 串接）
- `VERSION`（0.5.0.6 → 0.5.0.7）

## 修復紀錄

- **stage_debs 遺漏**：`chroot-install-target-setup.sh` 的 `build_debs` 已含 `strawwu-initramfs-hooks`，但 `stage_debs` 迴圈遺漏，導致 Calamares chroot 無法從 `staged-debs/` 安裝本套件。已補入 `stage_debs` 並新增 preflight 守門檢查。

## 已知限制 / Hermes 後續

1. **Live ISO**：本階段不改 initrd splice；`StrawWU-0.5.0.7-amd64.iso` 自 0.5.0.6 複製供 preflight 版本對齊。完整 squashfs 含新 deb 需另跑 `make release-iso`。
2. **Calamares initramfs 模組**：仍早於 target_setup 執行一次；target_identity 的 `update-initramfs` 負責最終磁碟 initrd（設計如此）。
3. **W8-doc-handbook**：留待下一階段。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-initramfs-hooks
make preflight-iso-before-boot
```

## 建議 commit message

```
feat(w8): add strawwu-initramfs-hooks deb for installed disk boot

- Strip casper/live-boot initramfs-tools hooks; enforce BOOT=local
- Add target-manifest entry before target-identity; stage deb in chroot-install
- Preflight + unit tests; VERSION 0.5.0.7
Tests: make test-initramfs-hooks PASS; make preflight-iso-before-boot PASS (release-iso)
```

## 下一步

Hermes mark PASS → 自動啟動 **w8-doc-handbook**（勿問使用者）。
