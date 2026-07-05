# W1-F2 Nosnap 階段報告

| 任務 | W1-F2-nosnap |
|------|--------------|
| 版本 | 0.4.1.3 |
| 日期 | 2026-07-05 |
| Worker | 階段 4/47（w1-f2-nosnap） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| Nosnap 強化腳本 | `os-image/scripts/chroot-nosnap-harden.sh` |
| Preflight 測試 | `tests/preflight/test-nosnap.sh` |
| Meta 審計基線 | `docs/plans/baselines/nosnap-audit.json` |
| Makefile | `test-nosnap`、`nosnap-harden`；`preflight` 含 nosnap |
| Release 基線 | `docs/plans/baselines/release-baseline.json`（nosnap 區塊） |
| Purge 測試 | `tests/preflight/test-purge-baseline.sh`（/snap stub 檢查） |

## 驗收命令輸出（2026-07-05T01:23:01-04:00，worker 階段 4/47 重跑）

### `make test-purge-baseline` — exit 0

```
=== W1-B1 purge-baseline preflight ===
PASS: rootfs absent snapd / squashfs absent snapd
PASS: rootfs absent snap-confine / squashfs absent snap-confine
PASS: retained ubuntu-minimal / ubuntu-desktop
PASS: rootfs /snap empty or stub only
PASS: squashfs ubuntu-* package count=14
=== W1-B1 purge-baseline done: PASS ===
```

Log: `/tmp/w1-f2-test-purge-baseline.log`

### `make test-flatpak` — exit 0

```
=== W1-F1 flatpak preflight ===
PASS: rootfs /usr/bin/flatpak present
PASS: rootfs flathub remote (repo config)
PASS: squashfs snapd absent
=== W1-F1 flatpak done: PASS ===
```

Log: `/tmp/w1-f2-test-flatpak.log`

### `make preflight` — exit 0

含 `test-ubuntu-clone.sh`、`test-branding.sh`、`test-purge-baseline.sh`、`test-flatpak.sh`、`test-nosnap.sh` 全部 PASS。

Log: `/tmp/w1-f2-preflight.log`

### chroot nosnap 強化（本 session）

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.nosnap-harden-ok` 存在 |
| apt pin | `/etc/apt/preferences.d/strawwu-nosnap`（Pin-Priority -1） |
| /snap | 空 stub + README |
| snapd 狀態 | `purge ok not-installed`；Recommends 顯示 **not installable** |
| squashfs sync | rootfs → squashfs-root rsync 完成 |

Log: `/tmp/w1-f2-nosnap-harden.log`

## 技術摘要

| 項目 | 狀態 |
|------|------|
| snapd / snap-confine | rootfs/squashfs 均未安裝（`ok installed`  absent） |
| ubuntu-desktop meta | **Recommends** snapd（非 Depends）；apt pin + hold 已 mask |
| /snap | 空 stub（僅 README），無 snap 內容目錄 |
| /var/lib/snapd | 不存在 |
| libsnapd-glib-2-1 / gir1.2-snapd-2 | 保留（cups/pipewire/update-manager 客戶端函式庫；無 snapd daemon） |
| flatpak / flathub | 不受影響，仍 PASS |
| ubuntu-desktop / ubuntu-desktop-minimal | 保留 |

## Meta 審計（nosnap-audit.json）

```json
{
  "meta_snap_references": [
    {"package": "ubuntu-desktop", "field": "Recommends", "masked": true},
    {"package": "ubuntu-desktop-minimal", "field": "Recommends", "masked": true}
  ],
  "snapd_installed": false,
  "client_libs_without_snapd": ["libsnapd-glib-2-1", "gir1.2-snapd-2"]
}
```

## 技術備註（治本）

1. **Recommends ≠ Depends**：Noble `ubuntu-desktop` 僅 Recommends snapd；StrawWU 以 `apt preferences` Pin-Priority -1 + `apt-mark hold` 雙重阻擋回裝，無需替換 meta 套件（W3-D1 再處理 strawwu-desktop meta）。
2. **/snap stub**：保留空目錄 + README，避免 legacy 路徑假設；purge 後 flatpak 安裝可能刪除 /snap，F2 腳本重建 stub。
3. **libsnapd-glib 殘留**：為 D-Bus 客戶端函式庫，cups-daemon / pipewire / update-manager 硬依賴；snapd daemon 缺席時安全，已文件化於 audit JSON。
4. **dpkg 跨 block 誤判**：audit `installed()` 初版 regex 跨 Package block 匹配；改為 per-block Status 解析。

## 已知 WARN / 後續 Wave

- rootfs 仍有 broken meta Depends（ubuntu-minimal → ubuntu-pro-client 等）；W3-D1 desktop-meta 替換。
- update-manager 仍依賴 gir1.2-snapd-2；W3-B3 update-notifier 可替換或 patch。
- chroot 內 apt 顯示 unmet Depends（gnome-control-center、xorg 等）；W1-B1/F1 已知，不阻擋 F2 nosnap 驗證。

## 變更檔案

- `os-image/scripts/chroot-nosnap-harden.sh`（新增）
- `tests/preflight/test-nosnap.sh`（新增）
- `docs/plans/baselines/nosnap-audit.json`（新增）
- `docs/plans/baselines/release-baseline.json`（nosnap 區塊）
- `tests/preflight/test-purge-baseline.sh`（/snap absent 亦 PASS）
- `tests/preflight/test-release-baseline.sh`（nosnap wave）
- `tests/preflight/test-ubuntu-clone.sh`（chroot-nosnap-harden 存在性）
- `Makefile`
- `VERSION`（0.4.1.3）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-purge-baseline
make test-flatpak
make preflight
```

## 建議 commit message

```
feat(w1): harden nosnap — mask snapd Recommends, stub /snap, audit meta

- Add chroot-nosnap-harden.sh with apt pin + /snap README stub
- Add test-nosnap preflight; extend release-baseline nosnap block
- Document meta Recommends audit in nosnap-audit.json
Tests: make test-purge-baseline PASS; make test-flatpak PASS; make preflight PASS
```

## 下一步

Hermes mark PASS → 自動啟動 **W1-S1-initrd**（依 kickoff 鎖序）。
