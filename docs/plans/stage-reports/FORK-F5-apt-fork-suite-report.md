# FORK-F5-apt-fork-suite — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f5-apt-fork-suite` |
| 版本 | `0.6.2.4`（`0.6.2.3` → `0.6.2.4`） |
| 基底 | Ubuntu 26.04 **resolute** fork baseline（F1–F4） |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07T20:50+08:00 |

## 摘要

建立 **strawwu-fork APT suite** 發佈管線：`publish-fork-debs.sh` 將 `os-image/fork/packages/output/` 的 fork 套件 `.deb` 發佈至 `dists/strawwu-fork/`；新增 branding `strawwu-fork.sources`、baseline JSON 與強化 preflight gate。目前 `packages` 陣列仍為空（scaffold-only）；實際 fork 套件註冊留待後續階段。

## 交付物

| 類型 | 路徑 |
|------|------|
| 發佈腳本 | `scripts/publish-fork-debs.sh` |
| 環境函式庫 | `os-image/scripts/lib/fork-apt-env.sh` |
| APT sources | `os-image/config/branding/etc/apt/sources.list.d/strawwu-fork.sources` |
| Baseline | `docs/plans/baselines/fork-apt-suite-baseline.json` |
| Target 配置 | `docs/plans/ubuntu-base-target.json`（`apt_fork_*` 欄位） |
| Preflight gate | `tests/preflight/test-fork-f5-apt-fork-suite.sh`（強化靜態+管線驗證） |
| Makefile | `publish-fork-debs` target |
| 文件 | `os-image/fork/packages/README.md`（發佈工作流程） |

## 架構

```
packages.json (publish_suite: strawwu-fork)
        │
        ▼ make build-fork-packages
os-image/fork/packages/output/*.deb
        │
        ▼ make publish-fork-debs
os-image/output/apt-fork-repo/
  dists/strawwu-fork/main/binary-amd64/{Packages.gz,Release,Release.gpg}
  pool/main/{letter}/{package}/*.deb
        │
        ▼ branding
strawwu-fork.sources → apt.strawwu.org (Signed-By keyring)
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.3` → `0.6.2.4` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `scripts/publish-fork-debs.sh` | **新增** fork APT 發佈管線 |
| `os-image/scripts/lib/fork-apt-env.sh` | **新增** suite/repo 路徑解析 |
| `os-image/config/branding/.../strawwu-fork.sources` | **新增** fork suite APT 源 |
| `docs/plans/ubuntu-base-target.json` | 新增 `apt_fork_suite/sources/repo_dir` |
| `docs/plans/baselines/fork-apt-suite-baseline.json` | **新增** baseline |
| `tests/preflight/test-fork-f5-apt-fork-suite.sh` | 強化 gate（管線+GPG 驗證） |
| `Makefile` | 新增 `publish-fork-debs` |
| `os-image/fork/packages/README.md` | 發佈工作流程 |

## 驗證命令輸出

### `make test-fork-f5-apt-fork-suite` — exit 0（~1.5s）

Log: `/tmp/fork-f5-test.log`

```
=== FORK-F5 apt-fork-suite gate ===
PASS: plan strawwu-fork-migration-plan.md
PASS: scripts/publish-fork-debs.sh
PASS: fork-apt-env.sh
PASS: strawwu-fork.sources
PASS: fork/packages registry
PASS: scripts/publish-debs.sh
PASS: tests/apt-repo/validate-apt-repo.py
PASS: strawwu-keyring/build-deb.sh
PASS: publish-fork-debs.sh syntax
PASS: fork-apt-env.sh syntax
PASS: publish-fork-debs.sh executable
PASS: Makefile publish-fork-debs target
PASS: Makefile test-fork-f5 target
PASS: strawwu-fork.sources suite name
PASS: strawwu-fork.sources Signed-By keyring
PASS: fork APT suite config alignment
PASS: publish-fork-debs --check
PASS: ephemeral fork APT GPG test key
PASS: strawwu-keyring deb build (fork test key)
PASS: strawwu-keyring test deb
PASS: publish-fork-debs pipeline (test deb)
PASS: fork Release / Release.gpg / Packages.gz
=== validate-apt-repo: PASS ===
PASS: validate-apt-repo.py (fork repo)
PASS: gpg --verify fork Release.gpg
PASS: publish-fork-debs --allow-empty (scaffold)
PASS: baseline written fork-apt-suite-baseline.json
FORK-F5 STATIC OK
```

### `make preflight` — exit 0（~199s，199156ms）

Log: `/tmp/fork-f5-preflight.log`（2514 行）

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
EXIT: 0
```

（preflight 全鏈 52 個靜態 gate；fork-f5 專項 gate 由 `make test-fork-f5-apt-fork-suite` 獨立執行）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f5-apt-fork-suite
make preflight
make publish-fork-debs --allow-empty  # scaffold-only，應輸出 allow-empty 訊息
```

（scaffold-only 驗證：`bash scripts/publish-fork-debs.sh --allow-empty`）

## 已知事項

- `packages.json` 的 `packages` 陣列目前為空；gnome-shell/mutter 等實際 fork 待後續註冊
- fork suite 與 main `resolute` suite 共用 `apt.strawwu.org` URI，以 suite 名稱區分
- `post-d7-software-sources` GUI 開關 fork suite 屬 deferred
- preflight 可能連帶更新 baseline JSON / release-manifest（side effect）

## Commit message（建議）

```
feat(fork-f5): add strawwu-fork APT suite publish pipeline

- Add publish-fork-debs.sh + fork-apt-env.sh for fork package debs
- Add branding strawwu-fork.sources and fork-apt-suite-baseline.json
- Extend ubuntu-base-target.json with apt_fork_* config
- Strengthen test-fork-f5-apt-fork-suite static + pipeline gate
- VERSION 0.6.2.3 → 0.6.2.4
Tests: make test-fork-f5-apt-fork-suite PASS; make preflight PASS
```
