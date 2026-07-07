# FORK-F4-package-overlays — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f4-package-overlays` |
| 版本 | `0.6.2.3`（`0.6.2.2` → `0.6.2.3`） |
| 基底 | Ubuntu 26.04 **resolute** fork baseline（F1–F3） |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07T20:27+08:00 |

## 摘要

建立 **fork upstream package overlays** 腳手架：`os-image/fork/packages/` 含 registry（`packages.json`）、`_template/` 範例目錄、建置/驗證腳本與 Makefile `build-fork-packages` 目標。目前 `packages` 陣列為空（僅驗證 scaffold）；實際 fork 套件註冊與 APT 發布留待 fork-f5。

## 交付物

| 類型 | 路徑 |
|------|------|
| Registry | `os-image/fork/packages/packages.json`（schema `strawwu-fork-packages/v1`） |
| Scaffold | `os-image/fork/packages/_template/`（PACKAGE.yaml + debian/ + build-package.sh） |
| 文件 | `os-image/fork/packages/README.md` |
| Gitignore | `os-image/fork/packages/.gitignore`（upstream tarballs、output/） |
| 建置腳本 | `os-image/scripts/build-fork-packages.sh` |
| 驗證腳本 | `os-image/scripts/validate-fork-package.sh` |
| 環境函式庫 | `os-image/scripts/lib/fork-packages-env.sh` |
| Makefile | `build-fork-packages` target |
| Preflight gate | `tests/preflight/test-fork-f4-package-overlays.sh`（強化靜態驗證） |

## 架構

```
ubuntu-base-target.json (fork_packages_dir)
        │
        ▼
os-image/fork/packages/packages.json
        │
        ├── _template/          ← 複製起點（status: template）
        ├── <pkgname>/          ← 註冊後的 fork 套件
        └── output/             ← 建置產物（gitignore）
        │
        ▼ make build-fork-packages
   validate scaffold → build registered packages
        │
        ▼ fork-f5
   strawwu-fork APT suite publish
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.2` → `0.6.2.3` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `os-image/fork/packages/packages.json` | **新增** registry |
| `os-image/fork/packages/_template/**` | **新增** scaffold |
| `os-image/fork/packages/.gitignore` | **新增** |
| `os-image/fork/packages/README.md` | 擴充工作流程文件 |
| `os-image/scripts/build-fork-packages.sh` | **新增** |
| `os-image/scripts/validate-fork-package.sh` | **新增** |
| `os-image/scripts/lib/fork-packages-env.sh` | **新增** |
| `Makefile` | 新增 `build-fork-packages` |
| `tests/preflight/test-fork-f4-package-overlays.sh` | 強化 gate |

## 驗證命令輸出

### `make test-fork-f4-package-overlays` — exit 0

Log: `/tmp/fork-f4-test.log`

```
=== FORK-F4 package-overlays gate ===
PASS: fork/packages README
PASS: fork/packages registry
PASS: fork/packages gitignore
PASS: fork package scaffold PACKAGE.yaml
PASS: fork package scaffold debian/control
PASS: fork package scaffold build-package.sh
PASS: build-fork-packages.sh
PASS: validate-fork-package.sh
PASS: fork-packages-env.sh
PASS: build-fork-packages.sh syntax
PASS: validate-fork-package.sh syntax
PASS: fork-packages-env.sh syntax
PASS: Makefile build-fork-packages target
PASS: ubuntu-base-target fork_packages_dir
PASS: validate _template
PASS: scaffold validation
PASS: build-fork-packages scaffold-only run
PASS: packages.json schema + ubuntu-base-target alignment
FORK-F4 STATIC OK
```

### `make preflight` — exit 0（~198s）

Log: `/tmp/fork-f4-preflight.log`

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
EXIT: 0
```

完整 preflight 含既有 wave/u26/fork baseline；exit code 0（2026-07-07T20:27+08:00 執行）。

### `make build-fork-packages` — exit 0

```
PASS: validate _template
==> validated _template
==> no registered fork packages (scaffold validated only)
EXIT: 0
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f4-package-overlays
make preflight
make build-fork-packages   # scaffold-only，應輸出「no registered fork packages」
```

## 已知事項

- `packages.json` 的 `packages` 陣列目前為空；gnome-shell/mutter 等實際 fork 待後續階段或 Post-MVP 策展
- `strawwu-shell` 採 `session-mode-overlay` 策略，短期不需 fork gnome-shell 原始碼
- APT suite 發布整合屬 fork-f5 範圍
- preflight 可能連帶更新 baseline JSON / release-manifest（side effect）

## Commit message（建議）

```
feat(fork-f4): add upstream package overlay scaffolding

- Add packages.json registry and _template/ debian scaffold
- Add build-fork-packages.sh, validate-fork-package.sh, fork-packages-env.sh
- Strengthen test-fork-f4-package-overlays static gate
- VERSION 0.6.2.2 → 0.6.2.3
Tests: make test-fork-f4-package-overlays PASS; make preflight PASS
```
