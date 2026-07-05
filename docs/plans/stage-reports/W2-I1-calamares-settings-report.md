# W2-I1 Calamares Settings 階段報告

| 任務 | W2-I1-calamares-settings |
|------|--------------------------|
| 版本 | 0.4.1.6 |
| 日期 | 2026-07-05 |
| Worker | 階段 7/47（w2-i1-calamares-settings） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-calamares-settings/` |
| Calamares 設定 | `os-image/debs/strawwu-calamares-settings/etc/calamares/` |
| 上游 exec 模組 | mount/fstab/grubcfg/machineid/umount 等（自 ubuntu-common 參照，無 snap） |
| 自訂模組 | automirror、pkgselect（上游 binary，保留安裝器行為） |
| post-install marker | `usr/local/lib/calamares/strawwu-post-install-marker.sh` |
| deb 建置 | `os-image/debs/strawwu-calamares-settings/build-deb.sh` |
| chroot 安裝 | `os-image/scripts/chroot-install-calamares-settings.sh` |
| Preflight 測試 | `tests/preflight/test-calamares-settings.sh` |
| Makefile | `test-calamares-settings`、`install-calamares-settings`；`preflight` 含本階段 |
| 管線更新 | `clone-ubuntu-base.sh`、`sync-calamares-installer.sh` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 取代 ubuntu-common | `strawwu-calamares-settings` deb；`Conflicts`/`Replaces`/`Provides` ubuntu-common |
| nosnap 對齊 | **不含** `snap-seed-glue`；chroot 移除 ubuntu-common 後同步清除 squashfs 殘留 |
| 分割策略 | `partition.conf` 維持 `devices.type: any`（QEMU virtio 相容） |
| branding | `settings.conf` → `branding: strawwu`（logo/show.qml 仍由 branding overlay 提供） |
| 目標安裝 purge | `packages.conf` 移除 `strawwu-calamares-settings`（原 ubuntu-common 項） |
| E2E overlay | `sync-calamares-installer.sh` 僅同步 E2E 腳本/systemd；設定由 deb 擁有 |

## 驗收命令輸出（2026-07-05T02:31 UTC-4，階段 7/47 worker 複驗）

### `make test-calamares-settings` — exit 0（~0.6s）

Log: `/tmp/w2-i1-test-calamares-settings.log`

```
=== W2-I1 calamares-settings done: PASS ===
```

關鍵檢查項（38 項 PASS）：deb 建置 `strawwu-calamares-settings_0.4.1.6_all.deb`（24K）、settings.conf exec phase + branding=strawwu、partition type=any、packages.conf 移除 strawwu-calamares-settings、deb 無 snap-seed-glue、rootfs+squashfs 已安裝 strawwu-calamares-settings、ubuntu-common absent、chroot marker 存在。

### `make preflight` — exit 0（~26s）

Log: `/tmp/w2-i1-preflight.log`

含 W0 baseline + branding + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-B2 bug-reporter + **W2-I1 calamares-settings** 全部 PASS（exit 0）。

### chroot 安裝

Log: `/tmp/w2-i1-chroot-install.log`

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.calamares-settings-ok` 存在 |
| deb | `strawwu-calamares-settings_0.4.1.6_all.deb`（~24K） |
| rootfs | `/etc/calamares/settings.conf` branding=strawwu |
| ubuntu-common | 已 purge；snap-seed-glue 已清除 |

## 技術備註（治本）

1. **設定所有權轉移**：Calamares 模組設定由 repo 內 deb 打包，不再依賴 apt 的 `calamares-settings-ubuntu-common`；clone 管線改為 chroot 安裝自製 deb。
2. **sync 職責縮減**：`sync-calamares-installer.sh` 不再覆寫 `etc/calamares/`（避免 runtime 與 deb 漂移）；僅保留 E2E guest runner 與 post-install marker 同步。
3. **nosnap 一致性**：ubuntu-common 內建 `snap-seed-glue` 與 W1-F2 衝突；自製 deb 排除該二進位，並在 squashfs rsync 後顯式刪除殘留。
4. **上游 exec 模組保留**：mount/fstab/grubcfg 等沿用 ubuntu-common 行為（cleanroom 參照上游 deb），避免重走 partition backend 打地鼠。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |
| Live UX 桌面化 | 待 W3-I2 |
| target identity / firstboot | 待 W5-I3、W5-N3 |
| Calamares E2E 重跑 | 設定來源變更後建議 Hermes 觸發 `make test-install-e2e` |

## 變更檔案清單

```
VERSION (0.4.1.5 → 0.4.1.6)
Makefile
os-image/debs/strawwu-calamares-settings/          (新增)
os-image/scripts/chroot-install-calamares-settings.sh (新增)
os-image/scripts/clone-ubuntu-base.sh
os-image/scripts/sync-calamares-installer.sh
os-image/config/calamares-installer/etc/calamares/modules/packages.conf
tests/preflight/test-calamares-settings.sh         (新增)
docs/plans/stage-reports/W2-I1-calamares-settings-report.md
```

## 建議 commit message

```
feat(w2): add strawwu-calamares-settings deb replacing ubuntu-common

- Package Calamares settings + upstream exec modules without snap-seed-glue
- chroot install replaces calamares-settings-ubuntu-common in rootfs
- sync-calamares-installer now E2E-only; settings owned by deb
Tests: make test-calamares-settings PASS; make preflight PASS
Version: 0.4.1.6
```

## 續跑狀態

- chroot marker：`.calamares-settings-ok` 已寫入
- 若 rootfs 不存在：先 `make clone-ubuntu-base`，再 `make install-calamares-settings`
- ISO 未重打包；下一階段或 Hermes 驗收前可選 `make dev-iso`

---

Hermes mark PASS → 自動啟動 **w2-r1-app-registry**（依 kickoff 鎖序）。
