# W2-B2 Bug Reporter 階段報告

| 任務 | W2-B2-bug-reporter |
|------|---------------------|
| 版本 | 0.4.1.5 |
| 日期 | 2026-07-05 |
| Worker | 階段 6/47（w2-b2-bug-reporter） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-bug-reporter/debian/` |
| CLI | `os-image/debs/strawwu-bug-reporter/usr/bin/strawwu-bug-report` |
| GTK consent UI | `os-image/debs/strawwu-bug-reporter/usr/bin/strawwu-bug-report-gtk` |
| 核心邏輯 | `os-image/debs/strawwu-bug-reporter/usr/lib/strawwu-bug-reporter/` |
| 隱私單元測試 | `os-image/debs/strawwu-bug-reporter/tests/test-privacy-filter.py` |
| deb 建置 | `os-image/debs/strawwu-bug-reporter/build-deb.sh` |
| chroot 安裝 | `os-image/scripts/chroot-install-bug-reporter.sh` |
| Preflight 測試 | `tests/preflight/test-bug-reporter.sh` |
| Makefile | `test-bug-reporter`、`install-bug-reporter`；`preflight` 含 bug-reporter |
| obs baseline | `docs/plans/baselines/obs-baseline.json`（`schema_ready=true`） |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 取代 apport | W1-B1 已 purge；本階段提供 `strawwu-bug-reporter` 替代 |
| CLI | `strawwu-bug-report` 建立 `.strawwu-bug` zip bundle |
| GTK | `strawwu-bug-report-gtk` 顯示收集項目 + upload consent checkbox（預設關） |
| 隱私過濾 | password/token/secret/SSH key/SSID/home 路徑 redaction |
| 預設行為 | 僅本地 bundle；`upload_opt_in=false`；上傳端點留待後續 Wave |
| Bundle schema | `manifest.json`、`system.json`、`journal.txt`、`dmesg.txt`、`logs/`、`user-notes.txt` |

## 驗收命令輸出（2026-07-05T02:15 UTC-4，worker 複驗）

### `make test-bug-reporter` — exit 0

Log: `/tmp/w2-b2-test-bug-reporter.log`

```
=== W2-B2 bug-reporter done: PASS ===
```

關鍵檢查項：deb 建置（14K）、4 項 privacy 單元測試、CLI dry-run/bundle/validate、rootfs+squashfs 已安裝 `strawwu-bug-reporter`、apport 套件 absent、`/var/log/strawwu` 存在、`obs-baseline.json` schema_ready=true。

### `make preflight` — exit 0（~25s）

Log: `/tmp/w2-b2-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-B2 bug-reporter 全部 PASS。

### chroot 安裝

Log: `/tmp/w2-b2-chroot-install.log`

| 項目 | 結果 |
|------|------|
| marker | `os-image/work/.bug-reporter-ok` 存在 |
| deb | `strawwu-bug-reporter_0.4.1.5_all.deb`（~14K） |
| rootfs CLI | `/usr/bin/strawwu-bug-report` 可執行 |
| consent 預設 | `/var/lib/strawwu/bug-upload-consent` → `upload_opt_in=false` |

## 技術備註（治本）

1. **apport 已移除**：W1-B1 purge 清除套件；postinst 額外寫入 `/etc/default/apport enabled=0` 防殘留。
2. **Bundle 格式對齊 OBS 計畫**：`.strawwu-bug` = zip；`manifest.json` 標記 `consent.auto_upload_default=false`。
3. **chroot 依賴**：沿用 W1-F1 模式，`apt-get download` + `dpkg -i --force-depends` 拉 python3-gi / gir1.2-gtk-3.0（W1-B1 後 meta 斷裂）。
4. **journal 收集較慢**：host 上 `journalctl --since 24h` 約 30–40s；preflight 可接受，後續可限縮 `-n` 行數。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 遠端上傳端點 | 未實作（consent 僅寫入 manifest；Hub 入口留 W4） |
| Hub「關於」bug 入口 | 待 W4-D3 |
| 結構化 JSON logging | 仍待 OBS4 |
| release-iso 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |

## VERSION

`0.4.1.4` → `0.4.1.5`（iterate）

## 建議 commit message

```
feat(w2): add strawwu-bug-reporter replacing apport

- CLI + GTK consent UI for local .strawwu-bug bundles
- Privacy filter (password/token/SSH/home paths)
- chroot install hook + preflight test-bug-reporter
Tests: make test-bug-reporter PASS, make preflight PASS
Version: 0.4.1.5
```

## 下一步

Hermes mark PASS → 自動啟動 **w2-i1-calamares-settings**（依 kickoff 鎖序）。
