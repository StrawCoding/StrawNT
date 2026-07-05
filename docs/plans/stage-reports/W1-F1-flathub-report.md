# W1-F1 Flathub 階段報告

| 任務 | W1-F1-flathub |
|------|---------------|
| 版本 | 0.4.1.2 |
| 日期 | 2026-07-05 |
| Worker | 階段 3/47（w1-f1-flathub） |
| 結果 | **Hermes mark PASS**（2026-07-05T01:19:42-0400 → next=w1-f2-nosnap） |

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-flatpak-setup/debian/` |
| deb 建置 | `os-image/debs/strawwu-flatpak-setup/build-deb.sh` |
| chroot 安裝 | `os-image/scripts/chroot-install-flatpak-setup.sh` |
| Preflight 測試 | `tests/preflight/test-flatpak.sh`（W1-F1 完整驗證） |
| Makefile | `test-flatpak`、`install-flatpak-setup`；`preflight` 含 flatpak |
| 共用函式 | `tests/preflight/lib/common.sh`（`_dpkg_pkg_installed` 修 pipefail SIGPIPE） |

## 驗收命令輸出（2026-07-05T01:19 UTC-4，Hermes PASS 後 worker 重跑確認）

### `make test-flatpak` — exit 0

```
=== W1-F1 flatpak preflight ===
PASS: plan strawwu-flathub-plan.md
PASS: strawwu-flatpak-setup debian/control
PASS: strawwu-flatpak-setup debian/postinst
PASS: strawwu-flatpak-setup build-deb.sh
PASS: chroot-install-flatpak-setup.sh
PASS: flatpak setup marker present (.../os-image/work/.flatpak-setup-ok)
PASS: rootfs /usr/bin/flatpak present
PASS: rootfs flatpak package installed
PASS: rootfs strawwu-flatpak-setup installed
PASS: rootfs flathub remote (repo config)
PASS: squashfs /usr/bin/flatpak present
PASS: squashfs flatpak package installed
PASS: squashfs strawwu-flatpak-setup installed
PASS: squashfs flathub remote (repo config)
PASS: squashfs snapd absent
=== W1-F1 flatpak done: PASS ===
```

Log: `/tmp/w1-f1-test-flatpak-rerun.log`

### `make preflight` — exit 0

含 `test-ubuntu-clone.sh`、`test-branding.sh`、`test-purge-baseline.sh`、`test-flatpak.sh` 全部 PASS。

Log: `/tmp/w1-f1-preflight-rerun.log`

### chroot 安裝（前置 session 已完成）

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.flatpak-setup-ok` 存在 |
| chroot flatpak | `Flatpak 1.14.6` |
| deb 建置 | `strawwu-flatpak-setup_0.4.1.2_all.deb` 建置成功 |
| flathub config | `[remote "flathub"]` url=`https://dl.flathub.org/repo/` |

## 技術摘要

| 項目 | 狀態 |
|------|------|
| flatpak CLI | rootfs/squashfs `/usr/bin/flatpak` 1.14.6 |
| strawwu-flatpak-setup deb | postinst 註冊 `flathub` system remote |
| Flathub remote | `/var/lib/flatpak/repo/config` 含 `[remote "flathub"]` |
| 預裝 runtime | 無（符合 kickoff 體積控制） |
| gnome-software | 未安裝 |
| snap 過渡包 | firefox/thunderbird/locale 已清除（安裝 flatpak 前） |

## 技術備註（治本）

1. **W1-B1 purge 後 apt 無法直接 install flatpak**：meta 套件 unmet Depends（ubuntu-pro-client、gnome-control-center 等）。改以 `apt-get download` 拉 flatpak 依賴 stack，`dpkg -i --force-depends` 安裝。
2. **snap 過渡包阻擋 apt**：firefox/thunderbird PreDepends snapd；F1 chroot 腳本先 `dpkg --purge --force-depends` 清除。
3. **preflight pipefail SIGPIPE**：`list_*_packages | grep -qx` 在 `set -o pipefail` 下 early-close 管線導致誤判；`common.sh` 改 `_dpkg_pkg_installed`（mktemp + grep 檔案）。

## 已知 WARN / 後續 Wave

- rootfs 仍有 broken meta Depends（ubuntu-minimal → ubuntu-pro-client 等）；W1-F2 / B 系列 meta 替換待處理。
- libsnapd-glib 殘留（snapd 已 purge）；W1-F2 nosnap 可進一步審計。
- chroot 內 `_apt` sandbox 權限 WARN（不阻擋 download）。

## 變更檔案

- `os-image/debs/strawwu-flatpak-setup/debian/control`（新增）
- `os-image/debs/strawwu-flatpak-setup/debian/postinst`（新增）
- `os-image/debs/strawwu-flatpak-setup/build-deb.sh`（新增）
- `os-image/scripts/chroot-install-flatpak-setup.sh`（新增）
- `tests/preflight/test-flatpak.sh`（W1-F1 完整驗證）
- `tests/preflight/lib/common.sh`（`_dpkg_pkg_installed`）
- `tests/preflight/test-ubuntu-clone.sh`
- `Makefile`
- `VERSION`（0.4.1.2）

## Hermes 驗收

Hermes 已 mark PASS（2026-07-05T01:19:42-0400）。Worker 重跑 `make test-flatpak`、`make preflight` 均 exit 0。

## 建議 commit message

```
feat(w1): add strawwu-flatpak-setup deb with Flathub system remote

- Add deb + chroot-install-flatpak-setup.sh for flatpak/flathub baseline
- Extend test-flatpak preflight; fix dpkg package probe SIGPIPE in common.sh
Tests: make test-flatpak PASS; make preflight PASS
```

## 下一步

**W1-F2-nosnap**（Hermes 已觸發 next stage）。
