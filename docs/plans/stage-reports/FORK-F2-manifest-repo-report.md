# FORK-F2-manifest-repo — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f2-manifest-repo` |
| 版本 | `0.6.2.1`（`0.6.2.0` → `0.6.2.1`） |
| 基底 | Ubuntu 26.04 **resolute** fork baseline snapshot（F1） |
| 狀態 | **PASS** |
| 完成時間 | 2026-07-07T19:47+08:00 |

## 摘要

將 fork 套件的 **include / remove / replace / pins** manifest 完整策展並納入 repo，對齊 W1-B1 遙測清除、W1-F2 nosnap、W5-B4 upstream init 關閉、W6-B5 meta audit 等既有 baseline。擴充 `fork-apply-manifest.sh` 支援 `replace.json` 與 `pins.txt` 套用，並新增 `overrides/etc/apt/preferences.d/strawwu-nosnap`。

## 交付物

| 類型 | 路徑 |
|------|------|
| Include manifest | `os-image/fork-base/packages/include.txt`（7 套件） |
| Remove manifest | `os-image/fork-base/packages/remove.txt`（16 套件） |
| Replace map | `os-image/fork-base/packages/replace.json`（5 映射） |
| APT pins | `os-image/fork-base/packages/pins.txt` |
| Config overrides | `os-image/fork-base/overrides/etc/apt/preferences.d/strawwu-nosnap` |
| Apply script | `os-image/scripts/fork-apply-manifest.sh`（remove → replace → include → overrides → pins） |
| Manifest metadata | `os-image/fork-base/manifest.json`（`curation` 區塊） |
| Preflight gate | `tests/preflight/test-fork-f2-manifest-repo.sh`（內容驗證強化） |

## Manifest 策展詳情

### remove.txt（16）

遙測／Pro／Snap：`snapd`、`snap-confine`、`apport*`、`whoopsie`、`ubuntu-report`、`ubuntu-pro-client*`、`ubuntu-advantage-*`

上游 meta（由 strawwu 取代）：`ubuntu-desktop`、`ubuntu-desktop-minimal`、`ubuntu-session`、`ubuntu-standard`、`update-notifier`

### replace.json（5）

| Ubuntu | StrawWU |
|--------|---------|
| `calamares-settings-ubuntu-common` | `strawwu-calamares-settings` |
| `ubuntu-minimal` | `strawwu-minimal` |
| `ubuntu-desktop` | `strawwu-desktop` |
| `ubuntu-desktop-minimal` | `strawwu-desktop` |
| `update-notifier` | `strawwu-update-notifier` |

### include.txt（7）

`linux-firmware`、`firmware-sof-signed`、`flatpak`、`gnome-software-plugin-flatpak`、`ca-certificates`、`curl`、`wget`

### pins.txt

- StrawWU kernel / `strawwu-*` 套件：`Pin-Priority: 1001`
- nosnap 阻擋：`snapd` / `snap-confine` / `ubuntu-core*` → `Pin-Priority: -1`

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.0` → `0.6.2.1` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `os-image/fork-base/packages/*` | 策展 manifest |
| `os-image/fork-base/overrides/` | nosnap apt pin |
| `os-image/fork-base/manifest.json` | `curation` metadata |
| `os-image/scripts/fork-apply-manifest.sh` | `apply_replace` + `apply_pins` |
| `tests/preflight/test-fork-f2-manifest-repo.sh` | schema + 內容 gate |

## 驗證命令輸出

### `make test-fork-f2-manifest-repo` — exit 0

Log: `/tmp/fork-f2-test.log`

```
=== FORK-F2 manifest-repo gate ===
PASS: packages/include.txt
PASS: packages/remove.txt
PASS: packages/replace.json
PASS: packages/pins.txt
PASS: fork-apply-manifest.sh syntax
PASS: fork-apply-manifest apply_replace
PASS: fork-apply-manifest apply_pins
PASS: nosnap apt override
PASS: replace.json schema + required mappings
PASS: remove.txt curated (16 packages)
PASS: include.txt curated (7 packages)
PASS: pins.txt apt preferences
PASS: manifest.json package references
FORK-F2 STATIC OK
```

### `make preflight` — exit 0（199.7s）

Log: `/tmp/fork-f2-preflight.log`

```
POST-MVP INFRASTRUCTURE OK
=== Ubuntu 26.04 closeout done: PASS ===
```

（完整輸出 2514 行；末尾含 fork_locked_sequence 7 stages、ubuntu-2604-closeout PASS）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-fork-f2-manifest-repo
make preflight
```

## 已知事項

- `ubuntu-minimal` 由 `replace.json` 處理（purge + install `strawwu-minimal`），不在 `remove.txt` 重複列出
- `apply_replace` 的 strawwu 套件安裝在 seed 模式下可能失敗（deb 尚未 stage）；完整安裝仍由 `chroot-install-target-setup` 負責
- snapshot 仍為 F1 產物；manifest 變更不觸發 snapshot 重建（F3/F6 處理 pipeline 整合）
- `base_mode` 仍為 `clone`（fork-f7-closeout 後才切換為 `fork`）

## Commit message（建議）

```
feat(fork-f2): curate fork package manifests in repo

- VERSION 0.6.2.0 → 0.6.2.1
- Curate include/remove/replace/pins aligned with W1/W5/W6 baselines
- fork-apply-manifest: apply_replace + apply_pins + nosnap override
- Strengthen test-fork-f2-manifest-repo content validation
Tests: make test-fork-f2-manifest-repo PASS; make preflight PASS
```
