# U26-M7-closeout — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `u26-m7-closeout` |
| 版本 | `0.6.1.6`（closeout bump；E2E 證據 `0.6.1.5`） |
| 基底 | Ubuntu 26.04 **resolute** |
| 狀態 | **PASS**（Hermes tick395 驗收） |
| 完成時間 | 2026-07-07 |

## 摘要

完成 Ubuntu 26.04 LTS Resolute 遷移 closeout：7 段 stage gate 全 PASS、`ubuntu-2604-status.json` 彙整、Teal 深色 HTML hermes-deliver 報告、VERSION bump 至 `0.6.1.6`。

## 治本修復（本階段）

### 1. `strawwu-initd` 缺少 `initramfs_hooks` lifecycle

**根因**：`strawwu-initramfs-hooks` 寫入 `lifecycle.initramfs_hooks`，但 `state.py` 未登記該 phase，導致 `install-target-setup` 在 chroot 內失敗。

**修復**：`LIFECYCLE_DEFAULTS` / `LIFECYCLE_ENUMS` 新增 `initramfs_hooks`；`setup-state.schema.json` 同步納入 `initramfs_hooks` phase；`test-init-tools.sh` lifecycle shape 斷言對齊。

**Hermes 回報**：`/tmp/u26-m7-preflight.log` W2-N1 `setup-state lifecycle shape` FAIL → 上述修復後重跑 exit 0。

### 2. `plymouth-set-default-theme` chroot 缺失

**根因**：resolute live rootfs chroot 無 `plymouth-set-default-theme`，`subprocess.run` 拋 `FileNotFoundError`。

**修復**：`configure_plymouth()` 以 `shutil.which` 偵測後跳過。

### 3. `.debs-rebuild-ok` 版本落後

**根因**：VERSION 升至 `0.6.1.5` 後未重跑 `install-target-setup`。

**修復**：`make build-os-debs` + `make install-target-setup` → marker `0.6.1.5`、rootfs 21 包對齊。

## 交付物

| 類型 | 路徑 |
|------|------|
| DoD | `docs/plans/ubuntu-2604-closeout/ubuntu-2604-dod.md` |
| HTML（hermes-deliver） | `docs/plans/ubuntu-2604-closeout/html/ubuntu-2604-closeout-report.html` |
| 簽名下載 | https://download.hermes.wastebase.xyz/ubuntu-2604-closeout-report.html?sig=LM_UuEPEZ-zIvBF5KUOgEPlCi0Ff36BfairQEf2K3yw |
| 驗證腳本 | `tests/ubuntu-2604-closeout/validate-ubuntu-2604-closeout.py` |
| HTML 渲染器 | `tests/ubuntu-2604-closeout/render-html.py` |
| Preflight gate | `tests/preflight/test-ubuntu-2604-closeout.sh` |
| 遷移狀態 JSON | `docs/plans/baselines/ubuntu-2604-status.json` |
| baseline | `docs/plans/baselines/ubuntu-2604-closeout-baseline.json` |

## 驗證命令輸出

### `make test-ubuntu-2604-closeout`（stage tests @0.6.1.5）— exit 0

Log: `/tmp/u26-m7-test-ubuntu-2604-closeout.log`

```
PASS: make test-u26-base-clone … test-u26-regression-e2e
PASS: ubuntu-2604-status.json 7/7 PASS
=== Ubuntu 26.04 closeout validation: PASS ===
```

### `make test-ubuntu-2604-all-pass` — exit 0

Log: `/tmp/u26-m7-test-ubuntu-2604-all-pass.log`

```
PASS: frozen ubuntu-2604-status.json all stages PASS
PASS: all 7 ubuntu 26.04 stages PASS
PASS: active base is 26.04.0 resolute
UBUNTU 26.04 ALL-PASS OK
```

### `make preflight` — exit 0（~200s）

Log: `/tmp/u26-m7-preflight.log`

```
=== W2-N1 init-tools done: PASS ===
…
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

## 證據路徑

| 項目 | 路徑 |
|------|------|
| release ISO（E2E） | `os-image/output/StrawWU-0.6.1.5-amd64.iso` |
| boot-test | `tests/boot/output/boot-result.json` |
| firstboot E2E | `tests/install-e2e/output/firstboot-e2e-result.json` |
| regression marker | `os-image/work/.regression-e2e-ok` |
| debs marker | `os-image/work/.debs-rebuild-ok` → `0.6.1.5` |

## 變更檔案清單

- `os-image/debs/strawwu-initd/usr/lib/strawwu-initd/state.py`
- `os-image/debs/strawwu-initd/tests/test-state.py`
- `docs/plans/schemas/setup-state.schema.json`（`initramfs_hooks` phase）
- `os-image/debs/strawwu-target-identity/usr/lib/strawwu-target-identity/core.py`
- `docs/plans/ubuntu-2604-closeout/ubuntu-2604-dod.md`
- `tests/ubuntu-2604-closeout/render-html.py`
- `tests/ubuntu-2604-closeout/validate-ubuntu-2604-closeout.py`
- `tests/preflight/test-ubuntu-2604-closeout.sh`
- `tests/preflight/test-ubuntu-2604-all-pass.sh`
- `tests/preflight/test-init-tools.sh`（lifecycle shape 含 initramfs_hooks）
- `Makefile`
- `VERSION`、`hub/package.json`、`components/Cargo.toml`

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-ubuntu-2604-all-pass
make preflight
```

## 備註

- M6 E2E 證據鎖定 `0.6.1.5`；closeout bump 至 `0.6.1.6` 不重跑 QEMU（`--skip-stage-tests` 讀取凍結 status JSON）。
- PASS 後自動啟動 `post-d1-strawwu-drivers`。
