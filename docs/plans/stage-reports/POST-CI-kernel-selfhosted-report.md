# POST-CI-kernel-selfhosted — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-ci-kernel-selfhosted` |
| 版本 | `0.7.0.4`（`0.7.0.3` → `0.7.0.4`） |
| 版本目標 | `0.8.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T12:14+08:00 |
| Worker 回合 | 階段 1/8（post-ci-kernel-selfhosted，worker 重跑驗證） |

## 摘要

實作 Post-MVP **Q6 self-hosted kernel build CI 管線**：

- 新增 `.github/workflows/kernel-build.yml`（self-hosted、週日 cron + workflow_dispatch）
- 新增 `scripts/ci-kernel-artifact.sh`（SHA256SUMS + `kernel-manifest.json`）
- 強化 `tests/preflight/test-ci-kernel-selfhosted.sh`（靜態接線 + stub manifest 驗證）
- 更新 `ci-baseline.json`：Q6 phase complete；`kernel-build.yml` 自 deferred 移除
- `Makefile` preflight 納入 `test-ci-kernel-selfhosted`

## 交付物

| 類型 | 路徑 |
|------|------|
| Kernel CI workflow | `.github/workflows/kernel-build.yml` |
| Artifact 腳本 | `scripts/ci-kernel-artifact.sh` |
| Preflight gate | `tests/preflight/test-ci-kernel-selfhosted.sh` |
| CI baseline | `docs/plans/baselines/ci-baseline.json` |
| Makefile | `preflight` 接線 + `test-ci-kernel-selfhosted` target |

## 架構

```
workflow_dispatch / cron (週日 02:00 UTC)
  → make kernel-build          # linux-image-strawwu .deb
  → make -C kernel test        # .build-ok + deb 存在
  → ci-kernel-artifact.sh      # SHA256SUMS + kernel-manifest.json
  → upload-artifact (90d)

preflight（靜態）:
  test-ci-kernel-selfhosted.sh
    → workflow 結構檢查
    → stub .deb manifest 數學
    → ci-baseline.json Q6 complete
```

### Kernel manifest schema

`kernel-manifest.json`（`strawwu-kernel-manifest/v1`）含：

- `product_version`、`kernel_abi`、`channel=kernel-ci`
- `git_sha`、`published_at`
- `artifacts[]`：`name`、`type`、`sha256`、`size_bytes`
- `build.runner= self-hosted`、`workflow`、`make_target`

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.3` → `0.7.0.4` |
| `.github/workflows/kernel-build.yml` | **新增** Q6 self-hosted kernel CI |
| `scripts/ci-kernel-artifact.sh` | **新增** kernel artifact manifest |
| `tests/preflight/test-ci-kernel-selfhosted.sh` | **強化** 完整 gate（原 stub fail） |
| `tests/preflight/test-ci-nightly.sh` | 移除 Q6 kernel gap from deferred |
| `docs/plans/baselines/ci-baseline.json` | Q6 phase + gaps_closed |
| `Makefile` | preflight 納入 test-ci-kernel-selfhosted |

## 測試證據

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-ci-kernel-selfhosted   # exit 0 — 2026-07-08T12:10+08:00
make preflight                   # exit 0 — ~243s，2026-07-08T12:14+08:00
```

### `make test-ci-kernel-selfhosted` — exit 0

Log: `/tmp/test-ci-kernel-selfhosted-worker.log`

```
=== POST-CI kernel selfhosted done: PASS ===
（全項 PASS：kernel-build.yml 結構、ci-kernel-artifact stub manifest、ci-baseline Q6 complete）
```

### `make preflight` — exit 0

Log: `/tmp/preflight-post-ci-kernel-worker.log`

含 POST-CI kernel selfhosted：`=== POST-CI kernel selfhosted done: PASS ===`（line 2747）

preflight 全程無 FAIL；W7-CI nightly 亦 PASS（deferred 不再含 kernel-build gap）。

## Hermes 部署備註

| 項目 | 說明 |
|------|------|
| Runner | 須為 `self-hosted`（對齊 Q6 決策 `decisions-2026-07-02.md`） |
| 權限 | `make kernel-build` 需 apt/build-essential（runner 須有 sudo） |
| 首跑 | `workflow_dispatch` 手動觸發驗證完整 kernel 編譯（20–60 min） |
| 排程 | 週日 02:00 UTC 自動重建 kernel deb |
| Artifact | `linux-image-strawwu_*.deb` + SHA256SUMS + kernel-manifest.json（90 天） |

## 已知限制 / 未涵蓋

| 項目 | 狀態 |
|------|------|
| 實際 kernel 完整編譯在 CI runner | 需 Hermes 首跑 `workflow_dispatch` 驗證 |
| CI1 rootfs 可重現 hash gate | 仍 deferred |
| production GPG 金鑰部署 | 仍 deferred（kernel CI 僅 SHA256，不簽 GPG） |
| nightly.yml 自動消費 kernel artifact | 未接線（nightly 仍本地 `swap-kernel`） |

## 建議 commit message

```
feat(post-ci): add Q6 self-hosted kernel build CI pipeline

- kernel-build.yml: weekly cron + dispatch on self-hosted runner
- ci-kernel-artifact.sh: SHA256SUMS + kernel-manifest.json
- test-ci-kernel-selfhosted.sh: static gate + baseline Q6 complete
Tests: make test-ci-kernel-selfhosted PASS; make preflight PASS
Version: 0.7.0.4
```

## 下一階段

Hermes mark PASS → 自動啟動 **post-w7-anticheat-substantive**（依 POST-MVP-AUTO-SEQUENCE）。
