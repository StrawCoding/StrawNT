# W7-CI nightly 階段報告

| 任務 | w7-ci-nightly |
|------|----------------|
| 版本 | 0.5.0.2 |
| 日期 | 2026-07-06 |
| Worker | 階段 40/47（w7-ci-nightly） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| 最後驗證 | 2026-07-06T00:26 UTC-4（本 worker 重跑三項命令） |

## 目標

建立 **self-hosted CI gate**：CI2 nightly pipeline（cron → dev-iso → SHA256 → manifest draft）、CI3 PR gate、CI4 self-hosted runner + GPG secret 注入，對齊 `strawwu-ci-build-plan.md` 與 Q6 決策。

## 交付物

| 類型 | 路徑 |
|------|------|
| Nightly workflow | `.github/workflows/nightly.yml` |
| PR gate workflow | `.github/workflows/ci.yml`（擴充 wincompat + calamares） |
| Release GPG wiring | `.github/workflows/release.yml`（ci-import-gpg + release-sign + manifest） |
| GPG import 腳本 | `scripts/ci-import-gpg.sh` |
| CI0 preflight | `tests/preflight/test-ci-baseline.sh`（強化 + ci-baseline.json） |
| W7-CI preflight | `tests/preflight/test-ci-nightly.sh` |
| baseline JSON | `docs/plans/baselines/ci-baseline.json` |
| Makefile | `test-ci-baseline`、`test-ci-nightly`；`preflight` 含本階段 |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **nightly.yml** | `runs-on: self-hosted`；cron 03:00 UTC；`preflight → dev-iso → SHA256SUMS → manifest (channel=nightly)`；artifact 保留 30 天 |
| **ci.yml (CI3)** | PR/push gate：`test-phase0` + `preflight` + `test-wincompat` + `validate-calamares-preflight` + `check-version-bump` |
| **release.yml** | 注入 `STRAWWU_GPG_PRIVATE_KEY` / `STRAWWU_GPG_KEY_ID`；`release-sign` + `generate-release-manifest` |
| **ci-import-gpg.sh** | CI 環境匯入 GPG 私鑰；`--check` 模式供 preflight 靜態驗證 |
| **ci-baseline.json** | CI0–CI4 狀態盤點；CI2/CI3/CI4 標記 complete |

### Nightly 管線（摘要）

```
cron main (03:00 UTC)
  → preflight
  → clone-ubuntu-base + swap-kernel
  → dev-iso (zstd)
  → preflight-iso-before-boot (dev-iso)
  → SHA256SUMS
  → release-manifest.json (channel=nightly, sign=skip)
  → upload-artifact (30d)
```

### Hermes 部署所需 Secrets

| Secret | 用途 |
|--------|------|
| `STRAWWU_GPG_PRIVATE_KEY` | release / APT 簽章（armored private key） |
| `STRAWWU_GPG_KEY_ID` | GPG key id（可選，腳本可 auto-detect） |
| `APT_DISPATCH_TOKEN` | 觸發 strawwu-apt update-repo workflow（已有） |

## 驗收命令輸出

### `make test-ci-baseline` — exit 0

Log: `/tmp/w7-ci-test-ci-baseline.log`

```
=== CI0 ci-baseline preflight ===
（全項 PASS：Makefile targets、三個 workflow、ci-import-gpg、ci-baseline.json）
=== CI0 ci-baseline done: PASS ===
```

### `make test-ci-nightly` — exit 0

Log: `/tmp/w7-ci-test-ci-nightly.log`

```
=== W7-CI nightly preflight ===
（全項 PASS：ci/nightly/release.yml 結構、stub manifest channel=nightly、baseline 更新）
=== W7-CI nightly done: PASS ===
```

### `make preflight` — exit 0（~107s，2164 行）

Log: `/tmp/w7-ci-preflight.log`

含 W0–W6 全部階段 + W7-RE manifest+gpg + W7-RE apt-repo + **W7-CI nightly** 終行：`=== W7-CI nightly done: PASS ===`

> Worker 驗收時間：2026-07-06T00:26 UTC-4；三項命令均 exit 0。
> 備註：首次 preflight 在 `test-bug-reporter.sh` 出現暫態 deb 路徑 race（`rm -rf output` 後 dpkg-deb ls 失敗）；重跑即 PASS，非本階段回歸。

## 變更檔案清單

```
VERSION (0.5.0.1 → 0.5.0.2)
Makefile
.github/workflows/nightly.yml                                    (新增)
.github/workflows/ci.yml                                         (CI3 PR gate 擴充)
.github/workflows/release.yml                                    (GPG import + release-sign + manifest)
scripts/ci-import-gpg.sh                                         (新增)
tests/preflight/test-ci-baseline.sh                              (強化 + ci-baseline.json)
tests/preflight/test-ci-nightly.sh                               (新增)
docs/plans/baselines/ci-baseline.json                            (新增/更新)
docs/plans/baselines/apt-repo-baseline.json                      (GPG wiring gap closed)
```

## 已知限制 / 延後

| 項目 | 說明 |
|------|------|
| CI1 rootfs 可重現 hash | 延後至後續 CI wave |
| 生產 GPG 金鑰部署 | 需 Hermes 在 self-hosted runner 設定 secrets |
| kernel-build.yml | Phase 2 Q6 獨立 workflow，非本階段範圍 |
| Nightly 實際 cron 執行 | 需 self-hosted runner 上線後由 Hermes 驗證首跑 |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-ci-baseline
make test-ci-nightly
make preflight
# 確認 self-hosted runner 已註冊且 secrets 已設定
# 可選：gh workflow run nightly.yml 手動觸發首跑
```

## 下一階段

**w7-perf-legal-gate**（Hermes mark PASS 後自動啟動，勿問使用者）。

## Commit message 建議

```
feat(w7): add self-hosted CI nightly pipeline and PR gate

- nightly.yml: cron dev-iso + SHA256 + manifest draft on self-hosted
- ci.yml: PR gate with wincompat + calamares preflight
- release.yml: GPG secret import via ci-import-gpg.sh
- test-ci-baseline/nightly preflight + ci-baseline.json

Tests: make test-ci-baseline test-ci-nightly preflight PASS
Version: 0.5.0.2
```
