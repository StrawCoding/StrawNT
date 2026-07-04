# StrawWU Upgrade / Recovery / Rollback 計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 1. 升級通道

| 路徑 | 機制 |
|------|------|
| 0.4 → 0.5 | ISO 重裝（保留 /home）或 `strawwu-upgrade` |
| 0.5 → 1.0 | 破壞性 migration 需備份提示 |
| deb 增量 | APT + strawwu meta 版本 pin |

## 2. strawwu-upgrade 行為

1. preflight：磁碟空間、state.json 版本、Registry schema
2. snapshot：`/var/lib/strawwu/backups/pre-upgrade-<ver>`
3. apt full-upgrade + strawwu meta
4. migration hooks（見下）
5. post-verify：boot-selfcheck + registry validate

## 3. 破壞性 Migration

| 資料 | 策略 |
|------|------|
| state.json | schema version field + migrator |
| App Registry | R5 migration crate |
| compat-db | 重建 + 保留 user profiles |
| Windows prefixes | 不刪；repair 指令 |

## 4. Update 失敗恢復

- apt：保留上一 kernel（≥2 個）
- initrd：initrd.img.old symlink
- meta 失敗：`strawwu-upgrade --rollback` 還原 snapshot
- 開機選單：GRUB 前一 kernel entry

## 5. Rescue Mode

- Live ISO「StrawWU Rescue」選項
- 掛載 installed root → `strawwu-initd repair`
- chroot：`strawwu-target-setup --repair-only`

## 6. Phase UPG0–UPG5

| Phase | 工作 |
|-------|------|
| UPG0 | state.json schema versioning |
| UPG1 | strawwu-upgrade CLI skeleton |
| UPG2 | pre-upgrade snapshot |
| UPG3 | Registry + state migrators |
| UPG4 | GRUB 多 kernel 保留策略 |
| UPG5 | rescue entry + 文件 |
