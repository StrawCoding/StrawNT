# U26-M5 Techrefs Refresh 階段報告

| 任務 | u26-m5-techrefs-refresh |
|------|-------------------------|
| 版本 | 0.6.1.4 |
| 日期 | 2026-07-06 |
| Worker | Cursor Agent（階段 1/8） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| 驗證時間 | 2026-07-06T10:19–10:23 UTC-4（companion check 重驗） |

## 摘要

將 `docs/technical-references/` 從 **noble 24.04** 上游文件基線刷新為 **Ubuntu 26.04 Resolute**：`refresh-technical-references.sh` 改由 `ubuntu-base-target.json` 推導 APT suite、拉取 resolute 套件原始碼、升級 kernel docs 至 v6.14.9，並自動再生 `catalog.json` 與 `.techrefs-refresh-ok` 標記。

## 交付物

| 類型 | 路徑 |
|------|------|
| Refresh 腳本 | `docs/technical-references/scripts/refresh-technical-references.sh` |
| 機器可讀索引 | `docs/technical-references/indexes/catalog.json`（`ubuntu_release: resolute`） |
| Phase 對照表 | `docs/technical-references/indexes/phase-validation-map.md` |
| README | `docs/technical-references/README.md` |
| 完成標記 | `docs/technical-references/.techrefs-refresh-ok` |
| 階段閘門 | `tests/preflight/lib/u26-stage-stub.sh`（u26-techrefs-refresh 完整驗證） |
| VERSION | `0.6.1.4` |

## 技術變更（治本）

1. **動態 suite 推導**：refresh 腳本讀取 `ubuntu-base-target.json` active codename（`resolute`），`apt-get source -t resolute` 拉取上游。
2. **套件版本升級**：casper 26.04.2、initramfs-tools 0.151ubuntu1、calamares 3.3.14、calamares-settings-ubuntu-common 26.04.12、grub2 2.14、plymouth git、libisoburn 1.5.6-1.1ubuntu4。
3. **Kernel docs**：linux-stable 從 v6.8.12 升至 **v6.14.9**（對齊 resolute kernel_upstream 6.14+）。
4. **catalog 自動再生**：refresh 結尾以 discovered upstream 目錄寫入 `catalog.json`；清除 noble 殘留目錄。
5. **階段閘門**：驗證 catalog suite、refresh 腳本 manpage URL、marker、linux-stable 非 6.8 世代。

## Resolute 上游套件（catalog.json）

| 套件 | 版本 |
|------|------|
| casper | 26.04.2 |
| initramfs-tools | 0.151ubuntu1 |
| plymouth | 24.004.60+git20250831.4a3c171d |
| libisoburn | 1.5.6 |
| grub2 | 2.14 |
| calamares | 3.3.14 |
| calamares-settings-ubuntu-common | 26.04.12 |
| linux-stable | v6.14.9 |

## 驗收命令輸出（2026-07-06，companion check 重驗）

### `make test-u26-techrefs-refresh` — exit 0（137 ms）

Log: `/tmp/u26-m5-test-techrefs-refresh.log`

```
PASS: plan strawwu-ubuntu-2604-migration-plan.md
PASS: refresh-technical-references.sh
PASS: catalog.json
PASS: techrefs-refresh marker
PASS: catalog ubuntu_release resolute (8 packages)
PASS: refresh script targets resolute manpages
PASS: .techrefs-refresh-ok marker suite=resolute
PASS: linux-stable v6.14.9 (resolute 6.14+ docs)
PASS: catalog strawwu_version 0.6.1.4 (VERSION 0.6.1.4)
PASS: u26-techrefs-refresh preflight stub
```

### `make preflight` — exit 0（184 s）

Log: `/tmp/u26-m5-preflight.log`

重點：全鏈 preflight 2497 行、1709 項 PASS，末尾 `POST-MVP INFRASTRUCTURE OK`。

### Refresh 執行 — exit 0（~100 s）

Log: `/tmp/u26-m5-refresh-techrefs.log`

重點：8 個 resolute apt source 同步、linux v6.14.9 docs clone、catalog 再生、總量 ~471–609M（upstream 本地快取，gitignored）。

## 已知限制 / 後續

| 項目 | 狀態 |
|------|------|
| `upstream/` 本機快取 | gitignored；需執行 refresh 腳本重建 |
| `docs/plans/strawwu-release-engineering-plan.md` noble 提及 | 可於 closeout 更新 |
| u26-m6-regression-e2e | 下一階段：release-iso boot-test + install-firstboot E2E |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-u26-techrefs-refresh
make preflight
```

## 建議 commit message

```
feat(u26-m5): refresh technical-references for Ubuntu 26.04 resolute

- refresh script: derive APT suite from ubuntu-base-target.json
- catalog.json: resolute packages + linux-stable v6.14.9 docs
- phase-validation-map + README updated for resolute paths
- u26-techrefs-refresh stage gate in u26-stage-stub.sh
Tests: make test-u26-techrefs-refresh PASS; make preflight PASS
Version: 0.6.1.4
```
