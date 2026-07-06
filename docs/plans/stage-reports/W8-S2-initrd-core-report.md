# W8-S2 initrd core 階段報告

| 任務 | w8-s2-initrd-core |
|------|-------------------|
| 版本 | 0.5.0.5 |
| 日期 | 2026-07-06 |
| Worker | 階段 43/47（w8-s2-initrd-core） |
| 最後驗證 | 2026-07-06T03:05 UTC-4（worker 階段 43/47 最終複驗） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

fork casper 核心 → `strawwu-live-init`；保留 `username=ubuntu` / `ID=ubuntu` 相容；initrd-splice 注入取代 runtime patch。

## 交付物

| 類型 | 路徑 |
|------|------|
| Live init 核心 | `os-image/initrd/strawwu-live-init/scripts/strawwu-live-init` |
| casper 相容 shim | `os-image/initrd/strawwu-live-init/scripts/casper-wrapper` |
| 清單 | `os-image/initrd/strawwu-live-init/MANIFEST.yaml` |
| baseline | `docs/plans/baselines/initrd-core-baseline.json` |
| splice 整合 | `os-image/scripts/initrd-splice.py`（`inject_strawwu_live_init`） |
| Preflight | `tests/preflight/test-initrd-core.sh` |
| Makefile | `test-initrd-core`；`preflight` 含本階段 |
| ISO | `os-image/output/StrawWU-0.5.0.5-amd64.iso`（release-iso，xz squashfs） |
| VERSION | `0.5.0.5` |

## 技術摘要

| 項目 | 說明 |
|------|------|
| 策略 | 保留 upstream `main.zst` splice；repo 擁有 `strawwu-live-init` 源碼取代 runtime `patch_casper_*` |
| 核心 fork | 自 Noble casper `/scripts/casper` 吸收 W1 已驗證 delta（光碟 hint、overlay insmod fallback、StrawWU branding） |
| 開機相容 | GRUB 仍 `boot=casper`；`/scripts/casper` 為 shim → `. /scripts/strawwu-live-init` |
| Live 使用者 | 預設 `USERNAME=ubuntu`；`etc/casper.conf` splice 維持 ubuntu/strawwu host |
| 注入時序 | `refresh_preserved_main` 先 `inject_strawwu_live_init` 再 overlays/branding |

## 驗收命令輸出（2026-07-06T03:05 UTC-4，worker 階段 43/47 最終複驗）

### `make test-initrd-core` — exit 0

```
=== W8-S2 initrd core (strawwu-live-init) preflight ===
PASS: plan strawwu-initrd-plan.md
PASS: W8-S2 kickoff
PASS: strawwu-live-init core script
PASS: casper compatibility shim
PASS: strawwu-live-init MANIFEST.yaml
PASS: initrd-core-baseline.json
PASS: initrd-splice.py
PASS: strawwu-live-init executable
PASS: casper-wrapper executable
PASS: core script identifies strawwu-live-init
PASS: core default USERNAME=ubuntu (casper compat)
PASS: core default BUILD_SYSTEM=StrawWU
PASS: core has optical live-media hint in find_livefs
PASS: core has overlay insmod fallback
PASS: MANIFEST schema v1
PASS: initrd-splice.py integrates strawwu-live-init
PASS: casper shim delegates to strawwu-live-init
PASS: staged initrd contains scripts/strawwu-live-init with strawwu-live-init marker
PASS: staged initrd contains scripts/casper with strawwu-live-init marker
PASS: staged initrd casper shim + core USERNAME=ubuntu
=== W8-S2 initrd core done ===
```

Log: `/tmp/w8-s2-test-initrd-core-verify.log`

### `make preflight-iso-before-boot`（release-iso）— exit 0

```
=== StrawWU ISO preflight (before boot-test) mode=release-iso strict=1 ===
PASS: ISO size 5596526592 bytes (>= 5GB)
PASS: SHA256SUMS validates
PASS: initrd size 68954242 bytes (30M–250M)
PASS: initrd structure verify (initrd-splice)
PASS: initrd early3 has strawwu modules
PASS: initrd early3 has ISO filesystem module
PASS: minimal.squashfs 1541615616 bytes (>= 1GB branded, mode=release-iso)
PASS: squashfs contains strawwu-boot-marker.service
PASS: squashfs contains strawwu-boot Plymouth theme
PASS: GDM live autologin configured for ubuntu
PASS: GRUB has username=ubuntu (casper live user)
PASS: build mode matches preflight (release-iso)
PASS: STRAWWU_SKIP_SQUASHFS=0 (full squashfs build)
=== ISO preflight done ===
```

Log: `/tmp/w8-s2-preflight-iso-verify.log`

### `make release-iso`（先前建置含 fork initrd）— exit 0

- ISO: `os-image/output/StrawWU-0.5.0.5-amd64.iso`（5.60GB，xz squashfs）
- SHA256: `a5cb085b8464a849afbdee1c17908da4bed889a418d1c550d87f5b7d0b58d623`
- 建置時間 ~23 min（terminal 766354）

## 變更檔案

- `os-image/initrd/strawwu-live-init/scripts/strawwu-live-init`（新增）
- `os-image/initrd/strawwu-live-init/scripts/casper-wrapper`（新增）
- `os-image/initrd/strawwu-live-init/MANIFEST.yaml`（新增）
- `docs/plans/baselines/initrd-core-baseline.json`（新增）
- `os-image/scripts/initrd-splice.py`（`inject_strawwu_live_init`；移除 runtime casper patch）
- `tests/preflight/test-initrd-core.sh`（新增）
- `Makefile`（`test-initrd-core`、preflight 串接）
- `VERSION`（0.5.0.4 → 0.5.0.5）

## 已知限制 / Hermes 後續

1. **W8-S3**：`casper-bottom` 全面審計替換留待下一階段。
2. **boot 參數**：kernel 仍 `boot=casper`；未改為 `boot=strawwu-live-init`（shim 過渡）。
3. **helpers**：`casper-helpers` / `casper-functions` 仍為 upstream initrd 內容。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-initrd-core
make preflight-iso-before-boot
```

## 建議 commit message

```
feat(w8): fork casper core into strawwu-live-init

- Add os-image/initrd/strawwu-live-init/ with forked live boot core + casper shim
- Wire initrd-splice.py inject_strawwu_live_init; drop runtime casper patches
- Add test-initrd-core preflight + initrd-core-baseline.json
Tests: make test-initrd-core PASS; make preflight-iso-before-boot PASS (release-iso)
```

## 下一步

Hermes mark PASS → 自動啟動 **w8-s3-initrd-bottom**（勿問使用者）。
