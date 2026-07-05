# W5-B4 Disable Upstream Init 階段報告

| 任務 | w5-b4-disable-upstream-init |
|------|-------------------------------|
| 版本 | 0.4.1.29 |
| 日期 | 2026-07-05 |
| Worker | 階段 27/47（w5-b4-disable-upstream-init） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

關閉上游初始化：cloud-init / gnome-initial-setup off；Calamares chroot 內 purge `ubuntu-desktop` / `ubuntu-desktop-minimal` / `ubuntu-session`，由 `strawwu-firstboot` 取代首次登入 UX。

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-disable-upstream-init/` |
| CLI | `/usr/bin/strawwu-disable-upstream-init` |
| 核心邏輯 | `usr/lib/strawwu-disable-upstream-init/core.py` |
| cloud-init 關閉 | `etc/cloud/cloud-init.disabled` + systemd mask |
| GNOME Initial Setup 關閉 | dconf keyfile + systemd mask + autostart rename |
| Manifest | `usr/share/strawwu/disable-upstream-init/disable-upstream-init-manifest.yaml` |
| Calamares hook | `shellprocess_disable-upstream-init.conf`（chroot，`dontChroot: false`） |
| settings 整合 | exec：`target_identity` → **`disable_upstream_init`** → `install_marker` |
| target 合流 | `target-manifest.yaml`、`install-init-manifest.yaml` |
| chroot 建置 | `chroot-install-target-setup.sh` 移除 ubuntu-desktop 過渡 reinstall、改跑 disable hook |
| Preflight | `tests/preflight/test-upstream-init-disabled.sh` |
| baseline | `docs/plans/baselines/upstream-init-disabled-baseline.json` |
| Makefile | `test-upstream-init-disabled`；`preflight` 含本階段 |
| Observability | `strawwu-observability-debug-plan.md` 新增 `disable-upstream-init.log`、`SWU-IN-004` |
| 關聯更新 | `test-purge-baseline.sh`、`test-desktop-stack.sh`（W5-B4 過渡完成邏輯） |

## 功能摘要

| 項目 | 實作 |
|------|------|
| cloud-init | `/etc/cloud/cloud-init.disabled`；mask `cloud-init*.service` / `cloud-init.target` |
| gnome-initial-setup | dconf `has-completed-setup=true`；mask 相關 unit；autostart desktop rename |
| 上游 meta purge | Calamares chroot：`ubuntu-desktop`、`ubuntu-desktop-minimal`、`ubuntu-session` |
| Live ISO | chroot-install 內 `--calamares-chroot` 同步套用（保留 `ubuntu-minimal`） |
| 生命週期 | `strawwu-initd set lifecycle.upstream_init_disabled running→done` |
| 標記 | `/var/lib/strawwu/setup/upstream-init-disabled.ok` |
| 錯誤碼 | `SWU-IN-004` |
| 日誌 | 結構化 JSON → `/var/log/strawwu/disable-upstream-init.log` |

## 驗收命令輸出

### 2026-07-05T09:44–09:46 UTC-4（worker 終驗，階段 27/47）

#### `make test-upstream-init-disabled` — exit 0（~0.8s）

Log: `/tmp/w5-b4-test-upstream-init-disabled.log`

```
=== W5-B4 disable-upstream-init done: PASS ===
```

關鍵檢查項：deb 結構、Calamares shellprocess 時序、6 項單元測試 PASS、CLI dry-run、`strawwu-disable-upstream-init_0.4.1.29_all.deb`（9.4K）。rootfs/squashfs 有 WARN（需 chroot 重跑，不阻斷）。

#### `make preflight` — exit 0（~112s）

Log: `/tmp/w5-b4-preflight.log`

含 W0 baseline + W1–W4 全部階段 + W5-N3/N4/D4/R4/I3 + **W5-B4 disable-upstream-init** 全部 exit 0（27 個子階段 PASS，無 FAIL）。

### chroot 同步

| 項目 | 結果 |
|------|------|
| `sudo chroot-install-target-setup.sh` | 未執行（環境 `sudo: unable to allocate pty`） |
| rootfs/squashfs | WARN：cloud-init.disabled、strawwu-disable-upstream-init、ubuntu-desktop purge 待 chroot 重跑 |
| 全新 Calamares 安裝路徑 | target-manifest 已含本 deb；hook 時序正確，不受 rootfs WARN 影響 |

## 技術備註（治本）

1. **取代而非共存**：cloud-init 與 gnome-initial-setup 與 StrawWU 安裝/initd/firstboot 管線衝突；以 marker + systemd mask + dconf 三層關閉，避免 live/installed 雙重首次設定。
2. **meta 過渡結束**：W3-D1 以 `strawwu-desktop` scaffold 過渡；W5-B4 在 Calamares chroot purge 上游 desktop meta，保留 `ubuntu-minimal` 至 W6-B5 審計。
3. **時序**：`disable_upstream_init` 在 `target_identity` 之後（GRUB/Plymouth 已套用）、`install_marker` 之前，確保 branding 完成後才移除上游 meta。
4. **postinst 輕量套用**：`--skip-meta-purge` 僅 mask/disable，供 live 套件安裝時不誤 purge。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| rootfs/squashfs chroot 同步 | 待 `sudo bash os-image/scripts/chroot-install-target-setup.sh` |
| ubuntu-minimal / ubuntu-pro-client 替代 | 待 W6-B5 meta audit |
| ubuntu-* 清零審計 | 待 W6-B5 |
| GDM greeter 品牌 | 待 w5-grt-session |

## VERSION

`0.4.1.28` → `0.4.1.29`（iterate）

## 建議 commit message

```
feat(w5): disable upstream cloud-init and gnome-initial-setup

- Add strawwu-disable-upstream-init deb with Calamares chroot hook
- Mask cloud-init/gnome-initial-setup; purge ubuntu-desktop metas
- test-upstream-init-disabled preflight + upstream-init-disabled baseline
Tests: make test-upstream-init-disabled PASS, make preflight PASS
Version: 0.4.1.29
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T09:46 UTC-4 | `[worker-DONE]` test-upstream-init-disabled + preflight exit 0 — 待 Hermes mark PASS |

## 下一階段

**w5-w4-wincompat-gui**（Hermes mark PASS 後自動啟動，勿問使用者）。
