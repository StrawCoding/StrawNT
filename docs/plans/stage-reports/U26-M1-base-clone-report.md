# U26-M1 Base Clone 階段報告

| 任務 | u26-m1-base-clone |
|------|-------------------|
| 版本 | 0.6.0.0 |
| 日期 | 2026-07-06 |
| Worker | 階段 1/8（Ubuntu 26.04 遷移）；續跑驗收 06:07 UTC-4 |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 摘要

將 StrawWU 上游基底從 **Ubuntu 24.04.2 noble** 切換至 **Ubuntu 26.04 LTS Resolute Raccoon**：下載官方 ISO、提取 layered squashfs rootfs、更新 `ubuntu-base-target.json` active 槽，並針對 resolute 修復 clone/purge/flatpak 管線相容性。

## 交付物

| 類型 | 路徑 |
|------|------|
| 版本鎖定 | `docs/plans/ubuntu-base-target.json`（active=26.04.0 resolute；previous=noble） |
| Clone marker | `os-image/work/.clone-ubuntu-base-ok` |
| ISO 快取 | `os-image/output/cache/ubuntu-26.04-desktop-amd64.iso` |
| Resolute rootfs | `os-image/work/rootfs/`（`VERSION_CODENAME=resolute`） |
| 階段測試 | `tests/preflight/lib/u26-stage-stub.sh`（擴充驗證） |
| 管線修復 | `os-image/scripts/clone-ubuntu-base.sh`、`chroot-purge-ubuntu-telemetry.sh`、`chroot-install-flatpak-setup.sh`、`chroot-install-target-setup.sh` |
| target-setup | `os-image/debs/strawwu-target-setup/usr/lib/strawwu-target-setup/core.py` |
| VERSION | `0.6.0.0`（`VERSION`、`hub/package.json`、`components/Cargo.toml`） |

## 技術變更（治本）

1. **active 切換**：`ubuntu-base-target.json` active → 26.04.0 / resolute；保留 `previous` noble 快照供回滾參照。
2. **Resolute ISO layered 提取**：`unsquashfs -ignore-errors` 處理 `minimal.en.squashfs` hardlink 衝突。
3. **chroot apt cdrom 來源**：clone 時停用 `cdrom.sources`（`file:///cdrom` 在 chroot 無效）。
4. **Purge 後桌面棧**：force-download 安裝 `gnome-shell`/`gdm3`/`gnome-control-center`（whoopsie 清除後 apt meta 斷裂）。
5. **Flatpak resolute 套件名**：`libfuse3-3` → 動態偵測 `libfuse3-4`；預拉 `libcomposefs1`。
6. **target-setup**：firstboot 先於 install-init；`strawwu-minimal`/`strawwu-l10n-ime` force-depends；optional `strawwu-keyring` 缺失不阻斷。

## 驗收命令輸出（2026-07-06）

### `make test-u26-base-clone` — exit 0

Log: `/tmp/u26-m1-test-worker.log`（worker 續跑 06:07）

```
PASS: plan strawwu-ubuntu-2604-migration-plan.md
PASS: ubuntu-base-target
PASS: active Ubuntu 26.04.0 resolute
PASS: clone marker .../os-image/work/.clone-ubuntu-base-ok
PASS: rootfs os-release resolute
PASS: u26-base-clone preflight stub
```

### `make preflight` — exit 0

Log: `/tmp/u26-m1-preflight-worker.log`（worker 續跑 06:07）

全 Wave 0–8 + Post-MVP 基礎設施腳本 PASS（~254s）。末行：`POST-MVP INFRASTRUCTURE OK`。

## 環境備註

- 本機曾缺失 `/dev/urandom`，導致 Python 測試中斷；已 `mknod` 恢復。
- `make clone-ubuntu-base` 需傳 `sudo STRAWWU_FORCE=1`（Makefile 未轉發 env）；建議 Hermes 驗收時使用：
  `sudo STRAWWU_FORCE=1 bash os-image/scripts/clone-ubuntu-base.sh`
- Loop 裝置耗盡時需確保 `/dev/loop*` 存在方可掛載 ISO。
- chroot 管線（purge → flatpak → target-setup）已於 06:02 完成；`.target-setup-ok` marker 存在。
- ISO 快取：`ubuntu-26.04-desktop-amd64.iso`（6.1G）；clone marker：`2026-07-06T05:46:28-04:00`。

## 已知限制 / 後續階段

| 項目 | 狀態 |
|------|------|
| `lifecycle.target_identity` | inner chroot 曾 `failed`；不影響本階段 base-clone 閘門 |
| Kernel swap | 仍為 noble 6.8 殘留；待 **u26-m2-kernel-rebase** |
| APT suite `resolute` | 待 **u26-m4-suite-migrate** |
| release-iso 回歸 | 待 **u26-m6-regression-e2e** |

## 變更檔案清單

- `VERSION`、`hub/package.json`、`components/Cargo.toml`
- `docs/plans/ubuntu-base-target.json`
- `os-image/scripts/clone-ubuntu-base.sh`
- `os-image/scripts/chroot-purge-ubuntu-telemetry.sh`
- `os-image/scripts/chroot-install-flatpak-setup.sh`
- `os-image/scripts/chroot-install-target-setup.sh`
- `os-image/debs/strawwu-target-setup/usr/lib/strawwu-target-setup/core.py`
- `tests/preflight/lib/u26-stage-stub.sh`
- `docs/plans/stage-reports/U26-M1-base-clone-report.md`

## 建議 commit message

```
feat(u26-m1): clone Ubuntu 26.04 resolute base and switch active target

- active ubuntu-base-target.json → 26.04.0 resolute; VERSION 0.6.0.0
- fix resolute ISO layered extract, cdrom apt, gnome-shell purge, libfuse3-4
- expand test-u26-base-clone stub (marker + os-release checks)
Tests: make test-u26-base-clone PASS; make preflight PASS
```

## Hermes 驗收建議

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-base-clone
make preflight
```

證據路徑見上表；請 Hermes mark PASS 後自動啟動 `u26-m2-kernel-rebase`。
