# FORK-F3-build-pipeline — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f3-build-pipeline` |
| 版本 | `0.6.2.2`（`0.6.2.1` → `0.6.2.2`） |
| 基底 | Ubuntu 26.04 **resolute** fork baseline（F1 snapshot + F2 manifest） |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07T20:08+08:00 |

## 摘要

將 build pipeline 正式支援 **fork-sync-base** 模式：`Makefile` 新增 `sync-base` 路由目標（依 `STRAWWU_BASE_MODE` / `ubuntu-base-target.json` → `base_mode` 分派 clone 或 fork）；`build-iso.sh`、`swap-kernel.sh` 與全部 chroot 安裝腳本改為接受 `.fork-sync-base-ok` 或 `.clone-ubuntu-base-ok` marker。新增共用函式庫 `lib/base-marker.sh` 與 `sync-base.sh` 分派腳本。

## 交付物

| 類型 | 路徑 |
|------|------|
| Fork sync 腳本 | `os-image/scripts/fork-sync-base.sh`（restore/seed snapshot） |
| Base 分派腳本 | `os-image/scripts/sync-base.sh` |
| 共用 marker 函式庫 | `os-image/scripts/lib/base-marker.sh` |
| Base mode 環境變數 | `os-image/scripts/lib/ubuntu-base-env.sh`（`STRAWWU_BASE_MODE`） |
| Makefile targets | `sync-base`、`fork-sync-base`、`repack-iso`、`validate-rootfs` |
| build-iso 整合 | `os-image/scripts/build-iso.sh`（`die_unless_base_marker`） |
| Chroot 腳本（8） | 接受 fork marker（purge / flatpak / nosnap / calamares / bug-reporter / update-notifier / target-setup / wincompat） |
| Preflight gate | `tests/preflight/test-fork-f3-build-pipeline.sh`（強化靜態驗證） |

## 架構

```
ubuntu-base-target.json (base_mode: clone|fork)
        │
        ▼ make sync-base  (STRAWWU_BASE_MODE override)
   ┌────┴────┐
clone       fork
   │          │
   ▼          ▼
clone-ubuntu-base   fork-sync-base
   │          │
   ▼          ▼
.clone-ubuntu-base-ok   .fork-sync-base-ok
   └────┬────┘
        ▼
  build-iso / chroot-* / swap-kernel
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.1` → `0.6.2.2` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `Makefile` | 新增 `sync-base` target 與 help |
| `os-image/scripts/lib/base-marker.sh` | **新增** 共用 marker 檢查 |
| `os-image/scripts/sync-base.sh` | **新增** base_mode 分派 |
| `os-image/scripts/lib/ubuntu-base-env.sh` | 匯出 `STRAWWU_BASE_MODE` |
| `os-image/scripts/build-iso.sh` | 使用 `die_unless_base_marker` |
| `os-image/scripts/swap-kernel.sh` | 接受 fork marker |
| `os-image/scripts/chroot-*.sh`（8 檔） | 接受 fork marker |
| `tests/preflight/test-fork-f3-build-pipeline.sh` | 強化 gate |

## 驗證命令輸出

### `make test-fork-f3-build-pipeline` — exit 0

Log: `/tmp/fork-f3-test.log`

```
=== FORK-F3 build-pipeline gate ===
PASS: fork-sync-base.sh
PASS: sync-base.sh
PASS: base-marker.sh
PASS: build-iso accepts fork marker
PASS: Makefile sync-base target
PASS: Makefile fork-sync-base target
PASS: ubuntu-base-env exports STRAWWU_BASE_MODE
PASS: chroot-purge-ubuntu-telemetry.sh accepts fork marker
PASS: chroot-install-target-setup.sh accepts fork marker
PASS: swap-kernel.sh accepts fork marker
PASS: STRAWWU_BASE_MODE resolves to clone
FORK-F3 STATIC OK
```

### `make preflight` — exit 0（199s，worker 重跑 2026-07-07T20:05+08:00）

Log: `/tmp/fork-f3-preflight.log`

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

完整 preflight 含 fork-f3 gate、全 baseline 與 ubuntu-2604-closeout；exit code 0。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f3-build-pipeline
make preflight
# 可選（需 root + snapshot）：
# STRAWWU_BASE_MODE=fork make fork-sync-base
# make dev-iso   # 在 fork marker 就緒後
```

## 已知事項

- `ubuntu-base-target.json` 的 `base_mode` 仍為 `clone`（fork-f7-closeout 後才切換為 `fork`）
- 本階段為靜態 gate + preflight；實際 `fork-sync-base` restore 與 ISO build 回歸留待 fork-f6
- preflight 連帶更新 baseline JSON / release-manifest / 0.6.2.2 debs（side effect）

## Commit message（建議）

```
feat(fork-f3): wire Makefile/build-iso for fork-sync-base mode

- Add sync-base dispatcher and lib/base-marker.sh shared checks
- build-iso, swap-kernel, chroot scripts accept .fork-sync-base-ok
- Export STRAWWU_BASE_MODE from ubuntu-base-target.json
- VERSION 0.6.2.1 → 0.6.2.2
Tests: make test-fork-f3-build-pipeline PASS; make preflight PASS
```
