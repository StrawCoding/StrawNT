# StrawWU 系統備份（時光機）

| 版本 | 1.1 |
|------|-----|
| 對照維度 | H13 備份/時光機（Mint Timeshift） |
| Stage | `post-backup-timeshift` |
| 版本目標 | `1.0.0-target`（實作 semver `0.7.0.10`） |

## 目標

1. **`strawwu-backup` deb**：rsync 快照（預設 PoC）、Btrfs subvolume 包裝、Timeshift CLI 整合
2. **Hub「備份與還原」分頁**：列出系統快照與升級前快照、建立快照、預覽還原計畫
3. **與 `post-upg-rollback` 對接**：共用 `/var/lib/strawwu/backups`，升級前快照由 `strawwu-upgrade snapshot` 建立

## 架構

```
/var/lib/strawwu/backups/
├── system/                         # strawwu-backup rsync/btrfs 快照
│   └── system-<ts>-<label>/
│       ├── manifest.json
│       └── files/...
└── pre-upgrade-<ver>/              # strawwu-upgrade 升級前快照
    ├── manifest.json
    └── state.json
```

### 後端選擇

| 後端 | 條件 | 行為 |
|------|------|------|
| `timeshift` | `/usr/bin/timeshift` 存在 | 呼叫 Timeshift `--create` / `--list` / `--restore` |
| `btrfs` | 根檔案系統為 btrfs | `btrfs subvolume snapshot` |
| `rsync` | 預設 | 複製 `backup-manifest.yaml` 中路徑 |

## CLI

```bash
strawwu-backup status --json
strawwu-backup list --json
strawwu-backup preflight --json
strawwu-backup snapshot create --label daily --json
strawwu-backup restore <name>            # dry-run（預設）
strawwu-backup restore <name> --apply      # 實際還原（需 root）
```

## Hub 整合

- 設定中心分頁 `backup`（`hub/resources/settings-manifest.json`）
- IPC：`backup:get-status`、`backup:list-snapshots`、`backup:create-snapshot`、`backup:preview-restore`
- 開發模式使用 `hub/tests/fixtures/backup-catalog.json`

## 驗收

```bash
make test-backup-timeshift
make preflight
```

## 後續（非本 stage）

- 排程快照（systemd timer）
- Polkit 授權還原
- 實機 Timeshift/Btrfs E2E（需 target 安裝）
