# POST-D7-software-sources — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-d7-software-sources` |
| 版本 | `0.6.3.9`（`0.6.3.8` → `0.6.3.9`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T09:14+08:00 |
| Worker 回合 | 階段 1/8（tick468 修復 + 重驗完成，待 Hermes mark） |

## 摘要

實作 Post-MVP D7 **strawwu-software-sources**：新增 Debian 套件（APT/Flatpak 軟體源 CLI + polkit 切換授權 + fixture 開發模式），並在 StrawWU Hub 新增「軟體源」分頁，列出 StrawWU 官方源、Flathub（唯讀）、Ubuntu 安全性更新（唯讀）與第三方源開關，整合 `strawwu-update-notifier`「檢查更新」。對標 Linux Mint `mintsources` / Ubuntu `software-properties-gtk` UX。

## 交付物

| 類型 | 路徑 |
|------|------|
| 計畫 | `docs/plans/strawwu-d7-software-sources-plan.md` |
| Debian 套件 | `os-image/debs/strawwu-software-sources/` |
| Hub 軟體源分頁 | `hub/src/main/software-sources-service.js` + renderer 面板 |
| Preflight gate | `tests/preflight/test-software-sources.sh` |
| Baseline | `docs/plans/baselines/software-sources-hub-baseline.json` |
| Python 單元測試 | `os-image/debs/strawwu-software-sources/tests/test-software-sources.py` |
| Hub 單元測試 | `hub/test/software-sources.test.js` |

## 架構

```
/etc/apt/sources.list.d/*.sources + flatpak remotes
        │
        ▼ strawwu-software-sources CLI (list|status|toggle|check-updates)
   polkit: xyz.wastebase.strawwu.software-sources.toggle
        │
        ▼ Hub software-sources-service.js (IPC)
   tab-software-sources UI — source cards + toggle + check updates
        │
        ▼ strawwu-update-notifier check (APT upgradable count)
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.8` → `0.6.3.9` |
| `hub/package.json` | 版本同步 |
| `os-image/debs/strawwu-software-sources/` | **新增** CLI、core.py、polkit、manifest、fixture、desktop |
| `hub/src/main/software-sources-service.js` | **新增** Hub 後端服務 |
| `hub/src/renderer/index.html` | 軟體源分頁 UI |
| `hub/src/renderer/renderer.js` | 軟體源渲染、切換、檢查更新 |
| `hub/src/renderer/styles.css` | 軟體源卡片樣式 |
| `hub/locales/en.json`, `zh.json` | sources.* i18n |
| `hub/resources/settings-manifest.json` | software-sources panel 註冊 |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-software-sources 建置 |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | chroot 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends strawwu-software-sources |
| `tests/preflight/test-software-sources.sh` | 擴充 OS 整合 + deb artifact 閘門 |
| `tests/preflight/test-greeter-session.sh` | 修復 output 目錄競態 rm |
| `tests/preflight/test-registry-hooks.sh` | 修復 pipefail+grep -q SIGPIPE 偶發 FAIL |
| `Makefile` | preflight 納入 test-software-sources |

## 功能範圍

### 已完成（v0.6 D7）

- `strawwu-software-sources list|status|toggle|check-updates` — APT deb822 掃描 + Flatpak remote 列舉
- Hub「軟體源」分頁：官方/Flathub/Security/第三方源卡片、啟停切換、檢查更新
- Flathub 與 Ubuntu Security 標記唯讀
- polkit `auth_admin_keep` 切換第三方源授權
- 整合 `strawwu-update-notifier check` 回報可升級套件數
- OS 映像整合：`build-os-debs` / `target-manifest` / `strawwu-desktop` Recommends
- fixture 開發模式（4 筆來源 + upgradable_count=3）

### 未做（deferred）

- fork suite GUI 開關（`strawwu-fork.sources`，FORK-F5 deferred）
- 獨立 GTK4 視窗（目前經 Hub 分頁 + desktop 入口 `--tab=software-sources`）
- 實機 Live ISO 軟體源切換 E2E（需 release-iso boot-test）

## Hermes tick466 修復

**根因**：`test-greeter-session.sh` 在 `rm -rf output/` 時與並行 preflight 競態，導致 `rm: cannot remove .../output: Is a directory`（log：`/tmp/hermes-tick466-preflight.log`）。

**修復**：
- `tests/preflight/test-greeter-session.sh` — 改為 `mkdir -p` + 只刪除舊 `.deb`，不再 `rm -rf` 整個 output 目錄
- `Makefile` — 將 `test-software-sources.sh` 納入 `preflight` 鏈（緊接 `test-flathub-hub.sh`）

## Hermes tick468 修復

**根因**：`test-registry-hooks.sh` 中 `"${REGISTRY_BIN}" scan --json | grep -q` 在 `set -o pipefail` 下，`grep -q` 提早關閉 pipe 導致 Rust CLI 收到 SIGPIPE（Broken pipe panic），preflight 在 Makefile:160 失敗（log：`/tmp/hermes-tick468-preflight.log`）。

**修復**：
- `tests/preflight/test-registry-hooks.sh` — 先快取 CLI JSON/`list` 輸出再 grep（同 W8-MVP `test-initramfs-hooks.sh` 模式）

## 驗證命令輸出

### `make test-software-sources` — exit 0（2026-07-08T09:09+08:00）

```
=== POST-D7 strawwu-software-sources preflight ===
PASS: plan strawwu-d7-software-sources-plan.md
...
PASS: strawwu-software-sources python tests
PASS: hub npm test (90 tests, 0 fail)
PASS: baseline unchanged software-sources-hub-baseline.json
=== POST-D7 strawwu-software-sources done: PASS ===
```

### `make preflight` — exit 0（2026-07-08T09:14+08:00）

```
=== POST-D7 strawwu-software-sources done: PASS ===
...
=== W5-R4 registry-hooks done: PASS ===
...
=== FORK-F7 closeout done: PASS ===
```

完整 log：
- `/tmp/hermes-d7-test-software-sources.log`
- `/tmp/hermes-tick468-preflight-rerun.log`（約 240s）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-software-sources
make preflight
```

## Commit message（建議）

```
feat(d7): add strawwu-software-sources Hub/GTK software sources UI

- New strawwu-software-sources deb: APT/Flatpak listing, polkit toggle, update check
- Hub software-sources tab with readonly Flathub/Security and third-party toggles
- Integrates strawwu-update-notifier for check-updates
Tests: make test-software-sources PASS, make preflight PASS
Version: 0.6.3.9
```

## 下一階段

Hermes mark PASS → 自動啟動 `post-ux-theme-curation`（依 POST-MVP-AUTO-SEQUENCE）
