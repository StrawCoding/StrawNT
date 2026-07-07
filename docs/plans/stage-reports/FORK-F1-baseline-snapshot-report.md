# FORK-F1-baseline-snapshot — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f1-baseline-snapshot` |
| 版本 | `0.6.2.0`（`0.6.1.6` → `0.6.2.0`） |
| 基底 | Ubuntu 26.04 **resolute**（u26-m7 closeout 驗證過的 rootfs） |
| 狀態 | **PASS**（Hermes tick398 驗收） |
| 完成時間 | 2026-07-07T19:30+08:00（worker 續跑驗證） |

## 摘要

自 u26 驗證過的 `os-image/work/rootfs`（marker `.clone-ubuntu-base-ok`）建立 fork baseline snapshot（`tar.zst`），並更新 `os-image/fork-base/manifest.json` 記錄 sha256、大小與 StrawWU 版本。VERSION bump 至 `0.6.2.0`。

## 交付物

| 類型 | 路徑 |
|------|------|
| Fork manifest | `os-image/fork-base/manifest.json` |
| Baseline snapshot | `os-image/fork-base/snapshots/fork-baseline-0.6.2.0-20260707T110640Z.tar.zst`（2.43 GiB，gitignore） |
| 完成 marker | `os-image/work/.fork-baseline-snapshot-ok` |
| Snapshot 路徑 marker | `os-image/work/.fork-baseline-snapshot-path` |
| 腳本 | `os-image/scripts/fork-baseline-snapshot.sh` |
| Makefile target | `fork-baseline-snapshot` |
| Preflight gate | `tests/preflight/test-fork-f1-baseline-snapshot.sh` |

## Snapshot 詳情

| 欄位 | 值 |
|------|-----|
| 檔名 | `fork-baseline-0.6.2.0-20260707T110640Z.tar.zst` |
| sha256 | `7e4b098f44f0ec31c1e9aa03668c3628ee56b09378da66c840a3c2bf534dd9f6` |
| size_bytes | `2611972740` |
| 壓縮比 | 6.89 GiB → 2.43 GiB（zstd -19，35.31%） |
| manifest status | `snapshot` |
| 來源 rootfs | `os-image/work/rootfs`（`.clone-ubuntu-base-ok`） |

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.1.6` → `0.6.2.0` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 `0.6.2` |
| `os-image/fork-base/manifest.json` | 寫入 snapshot 校驗與 metadata |
| `docs/plans/stage-reports/FORK-F1-baseline-snapshot-report.md` | 本報告 |

preflight 連帶更新 baseline JSON / release-manifest / 0.6.2.0 debs（side effect，非本階段核心交付）。

## 驗證命令輸出

### `make test-fork-f1-baseline-snapshot` — exit 0

Log: `/tmp/fork-f1-test-final.log`

```
=== FORK-F1 baseline-snapshot gate ===
PASS: fork-baseline-snapshot.sh
PASS: manifest.json
PASS: Makefile fork-baseline-snapshot target
FORK-F1 STATIC OK
```

### `make preflight` — exit 0（~200s，2026-07-07T19:27+08:00）

Log: `/tmp/fork-f1-preflight.log`

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

（worker 續跑：exit 0，耗時 200426ms）

### `make fork-baseline-snapshot`（含 preflight + snapshot）— exit 0（~1183s）

Log: `/tmp/fork-f1-baseline-snapshot.log`

```
==> creating fork baseline snapshot: …/fork-baseline-0.6.2.0-20260707T110640Z.tar.zst
PASS: snapshot fork-baseline-0.6.2.0-20260707T110640Z.tar.zst sha256=7e4b098f44f0ec31…
==> fork baseline snapshot OK: … (2611972740 bytes)
```

sha256 實測與 manifest 一致。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f1-baseline-snapshot
make preflight
# 可選：sha256sum os-image/fork-base/snapshots/fork-baseline-0.6.2.0-*.tar.zst
```

## 已知事項

- Python `datetime.utcnow()` DeprecationWarning（不影響功能；可於後續階段修正）
- snapshot 目錄在 `.gitignore`，不 commit 至 repo
- `base_mode` 仍為 `clone`（fork-f7-closeout 後才切換為 `fork`）

## Commit message（建議）

```
feat(fork-f1): capture u26-validated rootfs as fork baseline snapshot

- VERSION 0.6.1.6 → 0.6.2.0
- manifest.json status=snapshot with sha256/size
- snapshot: fork-baseline-0.6.2.0-20260707T110640Z.tar.zst (2.43 GiB)
Tests: make test-fork-f1-baseline-snapshot PASS; make preflight PASS
```
