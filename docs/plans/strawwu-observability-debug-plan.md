# StrawWU Observability / Debug 計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 1. Log 位置規範

| 子系統 | 路徑 |
|--------|------|
| boot-selfcheck | `/var/log/strawwu/boot-selfcheck.log` |
| install (Calamares) | `/var/log/strawwu/install.log` |
| target-setup | `/var/log/strawwu/target-setup.log` |
| target-identity | `/var/log/strawwu/target-identity.log` |
| disable-upstream-init | `/var/log/strawwu/disable-upstream-init.log` |
| firstboot | `/var/log/strawwu/firstboot.log` |
| App Registry | `/var/log/strawwu/app-registry.log` |
| update/upgrade | `/var/log/strawwu/update.log` |
| Windows compat | `/var/log/strawwu/wincompat.log` |
| Hub | journal `strawwu-hub` |

## 2. .strawwu-bug Bundle Schema

```
bundle.strawwu-bug (zip)
├── manifest.json
├── system.json      # VERSION, uname, machine-id hash
├── journal.txt      # 24h filtered
├── dmesg.txt
├── logs/            # 上述 strawwu/*.log
├── registry.json    # optional summary
└── user-notes.txt
```

## 3. 隱私過濾規則

- 過濾：`password`, `token`, `-----BEGIN`, SSID, `/home/*` 檔名
- journal：`-u strawwu-*` 優先
- 預設不含 `/home` 內容

## 4. User-facing Error Codes

| 碼 | 意義 |
|----|------|
| SWU-BT-001 | boot selfcheck failed |
| SWU-IN-001 | Calamares install failed |
| SWU-IN-002 | target setup chroot failed |
| SWU-IN-004 | disable upstream init failed |
| SWU-FB-001 | firstboot crash |
| SWU-FB-003 | firstboot state mismatch |
| SWU-AR-004 | app registry corrupt |
| SWU-UP-005 | upgrade rollback triggered |
| SWU-WC-006 | Windows compat launch failed |
| SWU-FP-007 | flatpak setup failed |
| SWU-RE-008 | release manifest verify failed |

## 5. Phase OBS0–OBS4

| Phase | 工作 |
|-------|------|
| OBS0 | log 目錄 + logrotate |
| OBS1 | bug bundle schema + CLI |
| OBS2 | 隱私過濾單元測試 |
| OBS3 | Hub 顯示最近錯誤碼 |
| OBS4 | install/firstboot 結構化 JSON log |
