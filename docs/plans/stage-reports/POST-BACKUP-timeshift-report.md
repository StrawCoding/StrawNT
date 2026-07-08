# POST-BACKUP-timeshift — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-backup-timeshift` |
| 版本 | `0.7.0.10`（`0.7.0.9` → `0.7.0.10`） |
| 版本目標 | `1.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T13:55+08:00 |
| Worker 回合 | 階段 1/8 |

## 摘要

實作 Post-MVP H13 **strawwu-backup 時光機 PoC** 與 **Hub 備份與還原分頁**：

- 新增 `strawwu-backup` Debian 套件：rsync / Btrfs / Timeshift 三後端、共用 `/var/lib/strawwu/backups`
- Hub 新增 `backup` 分頁：快照列表、建立快照、預覽還原（dry-run）
- 與 `strawwu-upgrade` 升級前快照 hook 對接（同一 backup root）

## 交付物

| 類型 | 路徑 |
|------|------|
| Debian 套件 | `os-image/debs/strawwu-backup/` |
| Hub 服務 | `hub/src/main/backup-service.js` |
| Hub fixture | `hub/tests/fixtures/backup-catalog.json` |
| Preflight gate | `tests/preflight/test-backup-timeshift.sh` |
| Baseline | `docs/plans/baselines/backup-timeshift-baseline.json` |
| 計畫 | `docs/plans/strawwu-backup-plan.md` |
| Python 單元測試 | `os-image/debs/strawwu-backup/tests/test-backup.py` |
| Hub 單元測試 | `hub/test/backup.test.js` |

## 架構

```
strawwu-backup snapshot create
        │
        ▼
/var/lib/strawwu/backups/system/<name>/
  manifest.json + files/（rsync PoC）

strawwu-upgrade snapshot（既有）
        │
        ▼
/var/lib/strawwu/backups/pre-upgrade-<ver>/

Hub backup 分頁
  backup-service → strawwu-backup status/list/snapshot/restore --json
  （dev：fixture-catalog.json）
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.9` → `0.7.0.10` |
| `os-image/debs/strawwu-backup/` | **新增** CLI、core.py、manifest、fixture、tests |
| `hub/src/main/backup-service.js` | **新增** Hub 備份 IPC 服務 |
| `hub/src/renderer/index.html` | 備份分頁 UI |
| `hub/src/renderer/renderer.js` | 備份列表/建立/預覽還原 |
| `hub/resources/settings-manifest.json` | `backup` panel + config |
| `hub/locales/en.json`, `zh.json` | 備份 i18n |
| `os-image/scripts/build-os-debs.sh` | 納入 strawwu-backup |
| `os-image/debs/strawwu-target-setup/.../target-manifest.yaml` | 安裝順序 |
| `os-image/scripts/chroot-install-target-setup.sh` | staged-debs 同步 |
| `os-image/debs/strawwu-desktop/debian/control` | Recommends strawwu-backup |
| `tests/preflight/test-backup-timeshift.sh` | **擴充** 靜態 + CLI + Hub 閘門 |

## 功能範圍

### 已完成（PoC）

- `strawwu-backup` CLI：`status`、`list`、`preflight`、`snapshot create`、`restore`（預設 dry-run）
- rsync 快照（`/etc/strawwu`、`/var/lib/strawwu/setup`）
- Btrfs / Timeshift 後端偵測與包裝（實機需對應檔案系統/套件）
- 列出 `pre-upgrade-*` 升級快照並提供還原計畫（委派 `strawwu-upgrade --rollback`）
- Hub「備份與還原」分頁骨架 + fixture 模式測試

### 未做（留待後續）

- systemd 排程自動快照
- Polkit 授權 `--apply` 還原
- 實機 Timeshift/Btrfs release-iso E2E
- Playwright Hub UI 視覺回歸（本 stage 以 node --test 結構驗證）

## 測試證據

| 命令 | 結果 | 備註 |
|------|------|------|
| `make test-backup-timeshift` | exit 0 | ALL CHECKS PASS（含 test-backup.py、CLI --json、hub backup.test.js） |
| `make preflight` | exit 0 | 全量 preflight 通過（含 hub npm test） |
| `hub npm test` | exit 0 | 含 backup.test.js、structure.test.js |

證據路徑：

- `tests/preflight/test-backup-timeshift.sh` 輸出
- `os-image/debs/strawwu-backup/tests/test-backup.py`
- `hub/test/backup.test.js`
- `docs/plans/baselines/backup-timeshift-baseline.json`

## 建議 Hermes 驗收

```bash
make test-backup-timeshift
make preflight
```

## Commit message（建議）

```
feat(backup): add strawwu-backup PoC and Hub backup panel

- strawwu-backup deb: rsync/btrfs/timeshift backends + upgrade hook
- Hub backup tab with snapshot list/create/preview-restore
- Integrate into build-os-debs, target-manifest, desktop Recommends
Tests: make test-backup-timeshift
Issue: post-backup-timeshift v0.7.0.10
```

## 續跑狀態

無阻塞；本 stage 實作與單元/preflight 測試已完成，等待 Hermes `trigger-verify` 與 mark。
