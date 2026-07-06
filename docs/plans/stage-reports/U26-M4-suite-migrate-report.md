# U26-M4 Suite Migrate 階段報告

| 任務 | u26-m4-suite-migrate |
|------|---------------------|
| 版本 | 0.6.1.3 |
| 日期 | 2026-07-06 |
| Worker | Cursor Agent（階段 1/8） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| 驗證時間 | 2026-07-06T09:53–09:57 UTC-4 |

## 摘要

將 StrawWU APT 發佈管線與 branding sources 模板從 **noble** 遷移至 **Ubuntu 26.04 Resolute**：`publish-debs.sh` 改由 `ubuntu-base-target.json` active codename 推導 suite；`dists/resolute/` 成為預設發佈路徑；`apt-repo-baseline.json` 與 `security-baseline.json` 同步更新。

## 交付物

| 類型 | 路徑 |
|------|------|
| APT 發佈腳本 | `scripts/publish-debs.sh`（`load_ubuntu_base_env` → `STRAWWU_APT_SUITE=resolute`） |
| APT baseline | `docs/plans/baselines/apt-repo-baseline.json`（`suite: resolute`） |
| Security baseline | `docs/plans/baselines/security-baseline.json`（`dists/resolute/Release.gpg`） |
| Branding sources | `os-image/config/branding/etc/apt/sources.list.d/strawwu.sources`（`Suites: resolute`） |
| Preflight 測試 | `tests/preflight/test-apt-repo.sh`、`test-security-baseline.sh` |
| 驗證工具 | `tests/apt-repo/validate-apt-repo.py`（預設 suite → resolute） |
| 階段閘門 | `tests/preflight/lib/u26-stage-stub.sh`（u26-suite-migrate 完整驗證） |
| VERSION | `0.6.1.3` |

## 技術變更（治本）

1. **動態 suite 推導**：`publish-debs.sh` 載入 `ubuntu-base-env.sh`，從 `ubuntu-base-target.json` active codename 取得 `STRAWWU_APT_SUITE`，不再硬編碼 `noble` fallback。
2. **Branding sources 模板**：`strawwu.sources` `Suites: noble` → `Suites: resolute`，與 resolute rootfs 對齊。
3. **Baseline JSON**：`apt-repo-baseline.json` 與 `security-baseline.json` 的 suite / `release_gpg` 路徑改為 `resolute`。
4. **Preflight 測試鏈**：`test-apt-repo.sh` 驗證 `dists/resolute/{Release,Release.gpg,Packages.gz}`；`validate-apt-repo.py` 預設 suite 改為 resolute。
5. **階段閘門**：`u26-suite-migrate` stub 檢查 active codename、baseline suite、sources 模板、publish-debs 不再 noble 硬編碼。

## 驗收命令輸出（2026-07-06，本 worker 重跑）

### `make test-u26-suite-migrate` — exit 0（~139 ms）

Log: `/tmp/u26-m4-test-suite-migrate.log`

```
PASS: plan strawwu-ubuntu-2604-migration-plan.md
PASS: publish-debs.sh
PASS: apt-repo-baseline
PASS: strawwu.sources
PASS: active Ubuntu 26.04.0 resolute
PASS: apt-repo-baseline suite resolute
PASS: strawwu.sources Suites: resolute
PASS: publish-debs.sh derives APT suite from ubuntu-base-target.json
PASS: u26-suite-migrate preflight stub
```

### `make preflight` — exit 0（~192 s，2497 行）

Log: `/tmp/u26-m4-preflight.log`

重點證據（apt-repo 段落）：

```
==> publishing 1 package(s) to .../tests/apt-repo/output/apt-repo
.../dists/resolute/main/binary-amd64/Packages.gz
.../dists/resolute/Release
.../dists/resolute/Release.gpg
=== validate-apt-repo: PASS ===
PASS: baseline written .../apt-repo-baseline.json
=== W7-RE apt-repo done: PASS ===
```

## 已知限制 / 後續

| 項目 | 狀態 |
|------|------|
| `docs/technical-references/` catalog 仍為 noble | 待 **u26-m5-techrefs-refresh** |
| `docs/plans/strawwu-release-engineering-plan.md` 文件仍提及 noble sources | 可於 techrefs 或 closeout 階段更新 |
| 生產 archive GPG 部署 | deferred（baseline） |
| fcitx5 依賴鏈 apt 修復 | 可於 regression 階段處理 |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-suite-migrate
make preflight
```

## 建議 commit message

```
feat(u26-m4): migrate APT suite noble→resolute in publish-debs and baselines

- publish-debs.sh: derive STRAWWU_APT_SUITE from ubuntu-base-target.json
- strawwu.sources: Suites resolute
- apt-repo-baseline + security-baseline + preflight tests updated
Tests: make test-u26-suite-migrate PASS; make preflight PASS
Version: 0.6.1.3
```
