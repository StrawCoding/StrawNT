# W8-S3 initrd bottom 階段報告

| 任務 | w8-s3-initrd-bottom |
|------|---------------------|
| 版本 | 0.5.0.6 |
| 日期 | 2026-07-06 |
| Worker | 階段 44/47（w8-s3-initrd-bottom） |
| 最後驗證 | 2026-07-06T03:34 UTC-4（worker 階段 44/47 最終複驗） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

casper-bottom 審計替換 → repo 擁有 `strawwu-live-bottom`（34 支 hook + ORDER）；`strawwu-live-init` 改跑 `/scripts/strawwu-live-bottom`；保留 `boot=casper` 相容 shim。

## 交付物

| 類型 | 路徑 |
|------|------|
| Live bottom hooks | `os-image/initrd/strawwu-live-bottom/scripts/`（34 hooks + ORDER） |
| 清單 | `os-image/initrd/strawwu-live-bottom/MANIFEST.yaml` |
| baseline | `docs/plans/baselines/initrd-bottom-baseline.json` |
| splice 整合 | `os-image/scripts/initrd-splice.py`（`inject_strawwu_live_bottom`） |
| 核心 runner | `os-image/initrd/strawwu-live-init/scripts/strawwu-live-init` |
| Preflight | `tests/preflight/test-initrd-bottom.sh` |
| Makefile | `test-initrd-bottom`；`preflight` 串接 |
| ISO | `os-image/output/StrawWU-0.5.0.6-amd64.iso`（release-iso，xz squashfs） |
| VERSION | `0.5.0.6` |

## 技術摘要

| 項目 | 說明 |
|------|------|
| 策略 | 自 Noble casper initrd 盤點 34 支 `casper-bottom` hook；整包 fork 至 `strawwu-live-bottom` |
| W1 遷移 | `25disable_cdrom.mount`（live-shutdown）自 overlays 併入 fork，刪除 `overlays/scripts/casper-bottom/` |
| 注入時序 | `refresh_preserved_main`：`inject_strawwu_live_init` → `inject_strawwu_live_bottom` → premount overlays |
| 相容 | `scripts/casper-bottom/ORDER` 僅保留委派至 `strawwu-live-bottom` 的 ORDER shim |
| 開機 | GRUB 仍 `boot=casper`；bottom 階段 log 顯示 `Running /scripts/strawwu-live-bottom` |

## 驗收命令輸出（2026-07-06T03:34 UTC-4，worker 階段 44/47 最終複驗）

### `make test-initrd-bottom` — exit 0

```
=== W8-S3 initrd bottom (strawwu-live-bottom) preflight ===
PASS: plan strawwu-initrd-plan.md
PASS: W8-S3 kickoff
PASS: strawwu-live-bottom ORDER
PASS: strawwu-live-bottom MANIFEST.yaml
PASS: initrd-bottom-baseline.json
PASS: initrd-splice.py
PASS: strawwu-live-init core
PASS: no duplicate casper-bottom overlay dir
PASS: strawwu-live-bottom has 34 hook scripts
PASS: ORDER identifies strawwu-live-bottom
PASS: ORDER paths use strawwu-live-bottom
PASS: live-shutdown hook (25disable_cdrom.mount) present
PASS: hook scripts executable
PASS: MANIFEST schema v1
PASS: initrd-splice.py integrates strawwu-live-bottom
PASS: strawwu-live-init runs strawwu-live-bottom
PASS: staged initrd contains strawwu-live-bottom ORDER
PASS: staged initrd has 34 strawwu-live-bottom hooks
PASS: staged casper-bottom compat ORDER delegates to strawwu-live-bottom
PASS: staged initrd core runs strawwu-live-bottom
=== W8-S3 initrd bottom done ===
```

Log: `/tmp/w8-s3-test-initrd-bottom.log`

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
PASS: minimal.squashfs 1541615616 bytes (>= 1GB branded, mode=release-iso)
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

Log: `/tmp/w8-s3-preflight-iso-verify.log`

### `make release-iso` — exit 0

- ISO: `os-image/output/StrawWU-0.5.0.6-amd64.iso`（5.60GB，xz squashfs）
- SHA256: `c9d2e312a00ae91ee80ebb046eb08920d4295c77191b3fde73e3202b63aefe21`
- 建置時間 ~21 min（`/tmp/w8-s3-release-iso.log`）

## 變更檔案

- `os-image/initrd/strawwu-live-bottom/`（新增：34 hooks + ORDER + MANIFEST.yaml）
- `os-image/initrd/strawwu-live-init/scripts/strawwu-live-init`（runner → strawwu-live-bottom）
- `os-image/initrd/overlays/scripts/casper-bottom/`（刪除，live-shutdown 已遷移）
- `os-image/scripts/initrd-splice.py`（`inject_strawwu_live_bottom`；overlays 跳過 casper-bottom）
- `docs/plans/baselines/initrd-bottom-baseline.json`（新增）
- `tests/preflight/test-initrd-bottom.sh`（新增）
- `tests/preflight/test-initrd-overlays.sh`（live-shutdown 改查 strawwu-live-bottom）
- `Makefile`（`test-initrd-bottom`、preflight 串接）
- `VERSION`（0.5.0.5 → 0.5.0.6）

## 已知限制 / Hermes 後續

1. **W8-S4**：initramfs deb hooks 留待下一階段。
2. **hook 內容**：除 `25disable_cdrom.mount` 外，其餘 33 支 hook 仍為 Noble upstream 邏輯（審計盤點完成、路徑擁有權轉移；逐支 StrawWU 化留待後續）。
3. **boot 參數**：kernel 仍 `boot=casper`；`casper-bottom` 僅 ORDER shim。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-initrd-bottom
make preflight-iso-before-boot
```

## 建議 commit message

```
feat(w8): fork casper-bottom into strawwu-live-bottom

- Add os-image/initrd/strawwu-live-bottom/ with 34 Noble casper-bottom hooks + ORDER
- Wire initrd-splice.py inject_strawwu_live_bottom; migrate live-shutdown from overlays
- Update strawwu-live-init to run /scripts/strawwu-live-bottom; casper-bottom ORDER shim
Tests: make test-initrd-bottom PASS; make preflight-iso-before-boot PASS (release-iso)
```

## 下一步

Hermes mark PASS → 自動啟動 **w8-s4-initramfs-hooks**（勿問使用者）。
