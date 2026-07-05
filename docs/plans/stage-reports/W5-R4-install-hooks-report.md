# W5-R4 Install Hooks 階段報告

| 任務 | w5-r4-install-hooks |
|------|---------------------|
| 版本 | 0.4.1.27 |
| 日期 | 2026-07-05 |
| Worker | 階段 25/47（w5-r4-install-hooks） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Linux/Flatpak 掃描寫入 User App Registry — APT 與 Flatpak 安裝管線 hook，於套件變更後自動登錄應用程式。

## 交付物

| 類型 | 路徑 |
|------|------|
| Rust scan 模組 | `components/strawwu-app-registry/src/scan.rs` |
| Registry upsert API | `components/strawwu-app-registry/src/registry.rs` — `upsert_from_scan` |
| CLI `scan` 命令 | `components/strawwu-app-registry/src/cli.rs` / `main.rs` |
| deb 套件 | `os-image/debs/strawwu-registry-hooks/` |
| APT hook | `etc/apt/apt.conf.d/99strawwu-registry-hooks` + `apt-post-invoke` |
| Flatpak trigger | `usr/share/flatpak/triggers/strawwu-registry-scan` |
| 掃描 CLI | `/usr/bin/strawwu-registry-scan` |
| Manifest | `usr/share/strawwu/registry-hooks/registry-hooks-manifest.yaml` |
| Preflight 測試 | `tests/preflight/test-registry-hooks.sh` |
| baseline JSON | `docs/plans/baselines/registry-hooks-baseline.json` |
| Makefile | `test-registry-hooks`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| Linux 掃描 | 遍歷 `/usr/share/applications`（可 `STRAWWU_LINUX_DESKTOP_DIRS` 覆寫），解析 `.desktop` → `kind=linux`、`source=manual` |
| Flatpak 掃描 | `flatpak list --app` 或 `STRAWWU_FLATPAK_LIST_FILE` fixture → `kind=flatpak`、`source=flatpak` |
| APT hook | `DPkg::Post-Invoke` → `strawwu-registry-scan --linux` |
| Flatpak hook | system trigger → `strawwu-registry-scan --flatpak` |
| upsert 語意 | 跳過 `protected` / `launcher` / Win32 `installer` 條目；其餘 upsert 或 reactivate |
| Phase 6 預設 | `execution_backend=native` |
| 三表分離 | 僅 User App Registry；不混 compat-db / AppDatabase |
| OS 整合 | `target-manifest.yaml`、`install-init-manifest.yaml`、`strawwu-desktop` Recommends |

## 驗收命令輸出（2026-07-05T08:55 UTC-4，worker 終驗）

### `make test-registry-hooks` — exit 0（~2.1s）

Log: `/tmp/w5-r4-test-registry-hooks.log`

```
=== W5-R4 registry-hooks done: PASS ===
```

關鍵檢查項：deb 結構、APT/Flatpak hook、cargo 21 unit tests、scan CLI Linux+Flatpak 整合、`strawwu-registry-scan` wrapper、skip env、deb 產物 `strawwu-registry-hooks_0.4.1.27_all.deb`。

### `make preflight` — exit 0（~115s）

Log: `/tmp/w5-r4-preflight.log`

含 W0 baseline + W1–W4 全部階段 + W5-N3/N4/D4 + **W5-R4 registry-hooks** 全部 exit 0（最終行 `=== W5-R4 registry-hooks done: PASS ===`）。

## 變更檔案清單

```
VERSION (0.4.1.26 → 0.4.1.27)
Makefile
components/strawwu-app-registry/src/scan.rs                    (新增)
components/strawwu-app-registry/src/lib.rs
components/strawwu-app-registry/src/cli.rs
components/strawwu-app-registry/src/main.rs
components/strawwu-app-registry/src/registry.rs
components/strawwu-app-registry/src/validate.rs
os-image/debs/strawwu-registry-hooks/                          (新增套件)
tests/preflight/test-registry-hooks.sh                         (新增)
docs/plans/baselines/registry-hooks-baseline.json              (新增)
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/debs/strawwu-install-init/usr/share/strawwu/install-init/install-init-manifest.yaml
os-image/debs/strawwu-desktop/debian/control
os-image/scripts/chroot-install-target-setup.sh
docs/plans/stage-reports/W5-R4-install-hooks-report.md         (本檔)
```

## 技術備註（治本）

1. **掃描邏輯在 Rust crate**：hook 腳本僅委派 `strawwu-app-registry scan`，與 Hub/launcher 共用 schema 與 upsert 語意。
2. **來源優先權**：launcher 與 Win32 installer 條目不被 APT/Flatpak 掃描覆寫，避免 Hub 移除與 wincompat 語意衝突。
3. **Flatpak 與 Linux 分離掃描**：Linux 掃描不含 `/var/lib/flatpak/exports`，避免重複登錄；Flatpak 走 `flatpak list`。
4. **無 legacy 複製**：v3.0 cleanroom；對齊 W2-R1 schema 1.0。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 卸載同步（掃描移除） | 待 **w6-r5** deep-uninstall |
| Hub Flathub install 後即時刷新 | Hub 讀檔；install 後可手動 refresh 或後續 IPC |
| chroot 重打包進 ISO | 需 `make dev-iso`/`release-iso` |
| Playwright E2E | 待 **w6-w6-wincompat-e2e** / install E2E |

## VERSION

`0.4.1.26` → `0.4.1.27`（iterate）

## 建議 commit message

```
feat(w5): add install pipeline registry hooks for Linux and Flatpak

- strawwu-app-registry scan CLI + upsert_from_scan; strawwu-registry-hooks deb
- APT DPkg::Post-Invoke and Flatpak trigger scan into app registry
Tests: make test-registry-hooks PASS, make preflight PASS
Version: 0.4.1.27
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T08:48 UTC-4 | `[worker-START]` companion supervisor started |
| 2026-07-05T08:55 UTC-4 | `[worker-DONE]` 終驗：`make test-registry-hooks` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w5-i3-target-identity**（Hermes mark PASS 後自動啟動，勿問使用者）。
