# POST-UPG-rollback — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-upg-rollback` |
| 版本 | `0.7.0.0`（`0.6.3.11` → `0.7.0.0`） |
| 版本目標 | `0.7.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T10:30+08:00 |
| Worker 回合 | 階段 1/8（worker-START 2026-07-08T10:26+08:00） |

## 摘要

實作 Post-MVP UPG **strawwu-upgrade + snapshot rollback + Rescue ISO 入口**：

- 新增 `strawwu-upgrade` Debian 套件：`preflight`、`snapshot`、`upgrade --dry-run`、`--rollback`
- Pre-upgrade snapshot 儲存於 `/var/lib/strawwu/backups/pre-upgrade-<ver>/`（`state.json` + `manifest.json`）
- Live ISO 新增 **StrawWU Rescue** GRUB 項目（`strawwu_rescue=1`）與 `strawwu-rescue-mode.service`
- 更新使用者文件（rescue-guide、upgrade-rescue-guide）反映 v0.7 已實作能力

## 交付物

| 類型 | 路徑 |
|------|------|
| Debian 套件 | `os-image/debs/strawwu-upgrade/` |
| Rescue ISO patch | `os-image/scripts/patch-iso-rescue-entry.sh` |
| Live rescue 模式 | `os-image/config/branding/usr/local/sbin/strawwu-rescue-mode` |
| Preflight gate | `tests/preflight/test-upgrade-rollback.sh` |
| Baseline | `docs/plans/baselines/upgrade-rollback-baseline.json` |
| Python 單元測試 | `os-image/debs/strawwu-upgrade/tests/test-upgrade.py` |

## 架構

```
升級前
  strawwu-upgrade preflight
  strawwu-upgrade snapshot  →  /var/lib/strawwu/backups/pre-upgrade-<ver>/
        │
        ▼
  strawwu-upgrade upgrade [--dry-run]
        │ apt dist-upgrade（實機）或 dry-run/fixture（測試）
        ▼ 失敗
  strawwu-upgrade --rollback  →  還原 state + initrd.img.old + target-setup repair

Live ISO
  GRUB「StrawWU Rescue」(strawwu_rescue=1)
        │
        ▼
  strawwu-rescue-mode.service → chroot 修復指引
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.11` → `0.7.0.0` |
| `hub/package.json`, `components/Cargo.toml` | 版本同步 |
| `os-image/debs/strawwu-upgrade/` | **新增** CLI、core.py、manifest、fixture、tests |
| `os-image/scripts/patch-iso-rescue-entry.sh` | **新增** GRUB/isolinux Rescue 項目 |
| `os-image/config/branding/.../strawwu-rescue-mode*` | **新增** Live rescue 模式 |
| `os-image/scripts/apply-branding.sh` | 整合 rescue patch + systemd enable |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-upgrade |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | chroot 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends strawwu-upgrade |
| `tests/preflight/test-upgrade-rollback.sh` | **實作** POST-UPG 靜態 + CLI 整合閘門 |
| `docs/user/rescue-guide.md` | v0.7 rollback / Rescue 更新 |
| `docs/user/handbook/upgrade-rescue-guide.md` | v0.7 操作步驟 |

## 功能範圍

### 已完成（v0.7 UPG）

- `strawwu-upgrade` CLI：`preflight`、`snapshot`、`upgrade --dry-run`、`list-snapshots`、`--rollback`
- Pre-upgrade snapshot（state.json + strawwu-* 套件版本 + boot 標記）
- Rollback 還原 state、initrd.img.old symlink、觸發 `strawwu-target-setup --repair-only`
- Live ISO「StrawWU Rescue」GRUB 項目（已於現有 iso-staging 驗證）
- Fixture 模式單元測試（無 apt/root 依賴）

### 未做（留待後續 stage）

- 實機 apt dist-upgrade E2E（需已安裝系統 + release APT repo）
- GRUB 自動保留 ≥2 kernel（UPG4 強化）
- compat-db 升級 migration
- Btrfs/ZFS 檔案系統層級 snapshot

## 驗證命令輸出

### `make test-upgrade-rollback` — exit 0（2026-07-08T10:27+08:00）

```
=== POST-UPG rollback preflight ===
PASS: plan strawwu-post-mvp-roadmap.md
PASS: plan strawwu-upgrade-recovery-plan.md
PASS: kickoff POST-UPG-rollback
PASS: strawwu-upgrade deb / CLI / core / manifest / fixture
PASS: build-deb.sh succeeded
PASS: strawwu-upgrade deb artifact
Ran 8 tests in 0.086s — OK
PASS: CLI version / preflight / upgrade --dry-run / --rollback
PASS: rescue entry present in staged grub.cfg
PASS: upgrade-rollback baseline aligned
=== POST-UPG rollback done: PASS ===
```

Log: `/tmp/post-upg-rollback-test.log`

### `make preflight` — exit 0（2026-07-08T10:31+08:00，耗時 ~242s）

```
1986 PASS / 0 FAIL
=== POST-V06 closeout done: PASS ===
```

Log: `/tmp/post-upg-preflight.log`

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-upgrade-rollback
make preflight
# 可選（需 iso-staging）：
bash os-image/scripts/patch-iso-rescue-entry.sh
grep -E 'StrawWU Rescue|strawwu_rescue=1' os-image/work/iso-staging/boot/grub/grub.cfg
```

## 產品決策 / 阻塞

無阻塞。GRUB 多 kernel 自動保留與 compat-db migration 依 upgrade-recovery-plan 留待 UPG3/UPG4。

## 接續

Hermes mark PASS → 自動啟動 **post-sec-secureboot-route**（依 POST-MVP-AUTO-SEQUENCE）。

## Commit message（建議）

```
feat(upg): add strawwu-upgrade snapshot rollback and rescue ISO entry

- strawwu-upgrade CLI: preflight, snapshot, upgrade --dry-run, --rollback
- pre-upgrade backups under /var/lib/strawwu/backups/pre-upgrade-<ver>
- Live ISO StrawWU Rescue GRUB entry (strawwu_rescue=1)
- VERSION 0.6.3.11 → 0.7.0.0
Tests: make test-upgrade-rollback PASS; make preflight PASS
Issue: post-upg-rollback v0.7.0.0
```
