# W6-F5 Target Flathub E2E 階段報告

| 任務 | w6-f5-target-flathub |
|------|----------------------|
| 版本 | 0.4.1.35 |
| 日期 | 2026-07-05 |
| Worker | 階段 32/47（w6-f5-target-flathub） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Calamares 安裝完成後，已安裝 target 系統具備 **flathub system remote**（`strawwu-flatpak-setup` postinst 註冊）。

## 交付物

| 類型 | 路徑 |
|------|------|
| E2E runner | `tests/install-e2e/run-target-flathub.sh` |
| 共用輔助 | `tests/install-e2e/lib.sh`（mount/check/inject flathub probe） |
| Preflight | `tests/preflight/test-target-flathub.sh` |
| baseline | `docs/plans/baselines/target-flathub-baseline.json` |
| Makefile | `test-target-flathub`、`test-target-flathub-static`；`preflight` 含 W6-F5 |
| 結果 JSON | `tests/install-e2e/output/target-flathub-result.json` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 安裝管線 | 沿用 install-e2e Calamares Python partition + target-setup staged debs |
| flathub 註冊 | `strawwu-flatpak-setup` postinst → `flatpak remote-add --system flathub` |
| target-manifest | 含 `strawwu-flatpak-setup`（W3-N2 已納入） |
| 檔案系統探測 | loop mount GPT p3 → 驗證 flatpak CLI、deb、repo config |
| 開機探測 | 注入 `strawwu-flathub-e2e.service` → BIOS boot → serial `TARGET_FLATHUB_OK` |
| 快速重測 | `STRAWWU_TARGET_FLATHUB_SKIP_INSTALL=1` 重用 `installed-boot-disk.img` |

## 變更檔案清單

```
tests/install-e2e/lib.sh                              (mount/check/inject helpers)
tests/install-e2e/run-target-flathub.sh               (新增)
tests/preflight/test-target-flathub.sh                (新增)
docs/plans/baselines/target-flathub-baseline.json     (新增)
Makefile
VERSION (0.4.1.34 → 0.4.1.35)
docs/plans/stage-reports/W6-F5-target-flathub-report.md (本檔)
```

## 驗收命令輸出（2026-07-05 UTC-4，worker 階段 32 最終重驗）

### `make test-target-flathub` — exit 0（~391s，`STRAWWU_TARGET_FLATHUB_SKIP_INSTALL=1`）

Log: `/tmp/w6-f5-test-target-flathub-rerun.log`

ISO: `StrawWU-0.4.1.33-amd64.iso`（沿用 W6-I4 `target-flathub-disk.img`）

結果 JSON: `tests/install-e2e/output/target-flathub-result.json`（tested: `2026-07-05T20:13:36-04:00`）

```json
{
  "version": "0.4.1.35",
  "status": "PASS",
  "flathub_marker": "TARGET_FLATHUB_OK",
  "install_ok": true,
  "filesystem_ok": true,
  "boot_ok": true
}
```

| 階段 | 耗時 | 證據 |
|------|------|------|
| calamares-preflight | <1s | validate-calamares-preflight ALL PASS |
| partition-probe | ~30s | `STRAWWU-PARTITION-PROBE-OK /dev/vda` |
| 檔案系統探測 | <1s | loop mount p3：`/usr/bin/flatpak`、`strawwu-flatpak-setup`、`[remote "flathub"]` |
| BIOS 開機探測 | 95s | `tests/install-e2e/output/logs/target-flathub-boot.log` 含 `TARGET_FLATHUB_OK` |

### `make preflight` — exit 0（~221s）

Log: `/tmp/w6-f5-preflight-rerun.log`

含 W0–W6-I4 全部階段 + **W6-F5 target-flathub**（`=== W6-F5 target-flathub done: PASS ===`）

## 技術摘要

| 項目 | 狀態 |
|------|------|
| live ISO flatpak | W1-F1 已驗證（squashfs） |
| target 安裝 flathub | target-setup manifest → `strawwu-flatpak-setup` dpkg postinst |
| 已安裝磁碟 flathub | `/var/lib/flatpak/repo/config` 含 `[remote "flathub"]` url=`https://dl.flathub.org/repo/` |
| runtime E2E | `flatpak remotes --system` 在已安裝系統開機後輸出 `TARGET_FLATHUB_OK` |

## 已知限制 / 後續

| 項目 | 說明 |
|------|------|
| 完整安裝 E2E | 本次以 `SKIP_INSTALL=1` 重用 W6-I4 磁碟；完整管線（含 Calamares install ~35min）邏輯與 W6-N5/I4 相同 |
| Flathub 應用安裝 | 本階段僅驗證 remote 存在；Hub 安裝流程由 W4-F3 覆蓋 |
| 下一階段 | **w6-b5-meta-audit**（Hermes mark PASS 後自動啟動） |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-target-flathub   # 完整 E2E（可設 STRAWWU_TARGET_FLATHUB_SKIP_INSTALL=1 快速重測）
make preflight
```

## Commit message（供 Hermes）

```
feat(w6): add target flathub E2E after Calamares install

- run-target-flathub.sh: filesystem + boot probe for flathub system remote
- lib.sh: mount_installed_root, check_flathub_remote_in_root, inject probe unit
- preflight gate + baseline for W6-F5

Tests: make test-target-flathub PASS, make preflight PASS
Version: 0.4.1.35
```
