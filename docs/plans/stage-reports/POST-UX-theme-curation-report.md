# POST-UX-theme-curation — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-ux-theme-curation` |
| 版本 | `0.6.3.10`（`0.6.3.9` → `0.6.3.10`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T09:33+08:00 |
| Worker 回合 | 階段 1/8（worker 驗證回合） |
| Git 狀態 | 變更未 commit（待 Hermes closeout） |
| Preflight 耗時 | ~255s（2928 行 log） |

## 摘要

實作 Post-MVP **深色主題策展**：新增 `strawwu-gtk-theme`（StrawWU-Dark GTK3/4 + GNOME Shell）與 `strawwu-icon-theme`（distributor-logo + Yaru-prussiangreen-dark 預設）Debian 套件；在 `strawwu-session` 加入 gsettings 預設深色（`prefer-dark`、Teal accent）；建立 `os-image/config/branding/themes/` 策展 manifest。對標 Zorin/Pop dark mode，Teal `#14B8A6` 與 `strawwu-colors.md` 一致。

## 交付物

| 類型 | 路徑 |
|------|------|
| 計畫 | `docs/plans/strawwu-ux-theme-curation-plan.md` |
| 策展 manifest | `os-image/config/branding/themes/theme-manifest.yaml` |
| GTK 主題套件 | `os-image/debs/strawwu-gtk-theme/` |
| Icon 主題套件 | `os-image/debs/strawwu-icon-theme/` |
| Session gsettings | `os-image/debs/strawwu-session/usr/share/glib-2.0/schemas/99_strawwu-session.gschema.override` |
| Preflight gate | `tests/preflight/test-ux-theme-curation.sh` |
| Baseline | `docs/plans/baselines/ux-theme-curation-baseline.json` |

## 架構

```
os-image/config/branding/themes/theme-manifest.yaml
        │
        ├─► strawwu-gtk-theme → /usr/share/themes/StrawWU-Dark/
        ├─► strawwu-icon-theme → distributor-logo.svg
        └─► strawwu-session gschema → gtk-theme + prefer-dark
                │
                ▼ strawwu-desktop Recommends (meta)
           target-manifest + build-os-debs + chroot-install
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.9` → `0.6.3.10` |
| `hub/package.json` | 版本同步 |
| `os-image/config/branding/themes/` | **新增** 策展 manifest + README |
| `os-image/debs/strawwu-gtk-theme/` | **新增** GTK/Shell 主題 deb |
| `os-image/debs/strawwu-icon-theme/` | **新增** icon branding deb |
| `os-image/debs/strawwu-session/` | gschema override + theme deps |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends theme packages |
| `os-image/scripts/build-os-debs.sh` | 納入主題套件建置 |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | chroot 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `tests/preflight/test-ux-theme-curation.sh` | 擴充完整閘門 |
| `Makefile` | preflight 納入 test-ux-theme-curation |

## 功能範圍

### 已完成（v0.6 UX theme）

- `strawwu-gtk-theme`：打包 StrawWU-Dark（Teal accent `#14B8A6`、深背景 `#0A0E14`）
- `strawwu-icon-theme`：StrawWU distributor-logo + Yaru-prussiangreen-dark 預設
- `strawwu-session` gsettings：`gtk-theme=StrawWU-Dark`、`color-scheme=prefer-dark`、`accent-color=teal`
- OS 映像整合：`build-os-debs` / `target-manifest` / `strawwu-desktop` Recommends
- branding overlay 既有 `99_strawwu-branding.gschema.override` 維持一致

### 未做（deferred）

- 淺色主題變體（StrawWU-Light）
- Hub 外觀設定分頁（使用者切換 dark/light）
- HiDPI 縮放實機驗證（HW T2）
- release-iso boot-test 主題視覺 E2E

## 測試證據

### `make test-ux-theme-curation`（2026-07-08T09:28）

```
$ make test-ux-theme-curation
=== POST-UX theme curation preflight ===
PASS: plan strawwu-ux-theme-curation-plan.md
PASS: plan strawwu-post-mvp-roadmap.md
PASS: kickoff POST-UX
PASS: theme curation manifest
PASS: theme curation README
PASS: StrawWU-Dark index.theme
PASS: StrawWU-Dark gtk-3.0 / gtk-4.0 / gnome-shell
PASS: gtk-3.0 uses Teal accent #14B8A6
PASS: gtk-3.0 uses deep dark background
PASS: gtk-3.0 uses filesystem imports
PASS: branding gschema sets StrawWU-Dark + prefer-dark
PASS: strawwu-gtk-theme / strawwu-icon-theme deb artifacts
PASS: strawwu-session gschema dark defaults
PASS: strawwu-desktop recommends theme packages
PASS: target-manifest + build-os-debs integration
PASS: python unit tests (gtk 6 + icon 4 + session 7)
PASS: baseline unchanged ux-theme-curation-baseline.json
=== POST-UX theme curation done: PASS ===
exit code: 0（55 項 PASS）
```

完整 log：`/tmp/test-ux-theme-curation.log`（58 行）

### `make preflight`（2026-07-08T09:33）

```
$ make preflight
...（全套 preflight 閘門，含 test-ux-theme-curation）
=== FORK-F7 closeout done: PASS ===
exit code: 0
```

完整 log：`/tmp/preflight-ux-theme.log`（2928 行，耗時 ~255s）

### 單元測試

- `os-image/debs/strawwu-gtk-theme/tests/test-gtk-theme.py` — 6 PASS
- `os-image/debs/strawwu-icon-theme/tests/test-icon-theme.py` — 4 PASS
- `os-image/debs/strawwu-session/tests/test-session.py` — 7 PASS（含 gschema）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-ux-theme-curation
make preflight
```

## 下一階段

Hermes mark PASS → 自動啟動 `post-v06-closeout`（依 POST-MVP-AUTO-SEQUENCE）

## Commit message（建議）

```
feat(post-ux): add strawwu-gtk-theme and strawwu-icon-theme dark curation

- Package StrawWU-Dark GTK/Shell theme and distributor-logo icon branding
- Add strawwu-session gschema defaults (prefer-dark, Teal accent)
- Integrate theme debs into build-os-debs, target-manifest, desktop meta
Tests: make test-ux-theme-curation PASS, make preflight PASS
Version: 0.6.3.10
```
