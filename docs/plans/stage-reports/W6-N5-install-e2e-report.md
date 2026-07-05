# W6-N5 install + firstboot E2E 階段報告

| 任務 | w6-n5-install-e2e |
|------|-------------------|
| 版本 | 0.4.1.33 |
| 日期 | 2026-07-05 |
| Worker | 階段 30/47（w6-n5-install-e2e） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Calamares 安裝 → 已安裝磁碟開機 → serial **FIRSTBOOT_OK**（headless firstboot E2E）。

## 交付物

| 類型 | 路徑 |
|------|------|
| firstboot `--e2e` 模式 | `os-image/debs/strawwu-firstboot/usr/lib/strawwu-firstboot/core.py` |
| CLI `--e2e` | `os-image/debs/strawwu-firstboot/usr/bin/strawwu-firstboot` |
| E2E runner | `tests/install-e2e/run-firstboot-e2e.sh` |
| overlay sync | `tests/install-e2e/sync-firstboot-overlay.sh` |
| guest bootloader + firstboot unit | `tests/install-e2e/guest/e2e-bootloader-setup.sh` |
| fast locale shellprocess | `tests/install-e2e/guest/shellprocess_e2e-locale.conf` |
| E2E settings 更新 | `tests/install-e2e/guest/settings.conf` |
| bootloader timeout 900s | `tests/install-e2e/guest/shellprocess_bootloader-e2e.conf` |
| mapfile 相容修正 | `tests/install-e2e/lib.sh`（`load_qemu_disk_args`） |
| Preflight | `tests/preflight/test-install-firstboot-e2e.sh` |
| baseline | `docs/plans/baselines/install-firstboot-e2e-baseline.json` |
| Makefile | `test-install-firstboot-e2e`；`preflight` 含 W6-N5 |
| 單元測試 | `test_run_e2e_writes_state`、`test_e2e_marker_constant` |

## 功能摘要

| 項目 | 實作 |
|------|------|
| E2E marker | `FIRSTBOOT_OK` → `/dev/ttyS0` + `/dev/kmsg` |
| Headless firstboot | `strawwu-firstboot run --e2e` 寫入 `lifecycle.firstboot=done`（真實 state，無 GTK） |
| 9p overlay | 安裝時從 guest share 覆寫 firstboot deb 源碼（免 ISO rebuild） |
| systemd | `strawwu-firstboot-e2e.service`（修正 ordering cycle） |
| 安裝管線 | 沿用 install-e2e Calamares Python partition + `e2e-bootloader-setup` |
| locale 治本 | 以 `shellprocess@e2e_locale` 取代 `localecfg`（避免 locale-gen 無限 hang） |

## 變更檔案清單

```
os-image/debs/strawwu-firstboot/usr/lib/strawwu-firstboot/core.py
os-image/debs/strawwu-firstboot/usr/bin/strawwu-firstboot
os-image/debs/strawwu-firstboot/tests/test-firstboot.py
tests/install-e2e/run-firstboot-e2e.sh          (新增)
tests/install-e2e/sync-firstboot-overlay.sh     (新增)
tests/install-e2e/guest/e2e-bootloader-setup.sh
tests/install-e2e/guest/shellprocess_e2e-locale.conf (新增)
tests/install-e2e/guest/settings.conf
tests/install-e2e/guest/shellprocess_bootloader-e2e.conf
tests/install-e2e/lib.sh
tests/install-e2e/run.sh
tests/install-e2e/partition-probe.sh
tests/preflight/test-install-firstboot-e2e.sh (新增)
tests/preflight/test-firstboot.sh
docs/plans/baselines/install-firstboot-e2e-baseline.json (新增)
Makefile
VERSION (0.4.1.32 → 0.4.1.33)
```

## 驗收命令輸出（2026-07-05 UTC-4）

### `bash tests/install-e2e/run-firstboot-e2e.sh`（等同 `make test-install-firstboot-e2e` 核心）— exit 0（~2557s）

Log: `/tmp/w6-n5-e2e-run5.log`

ISO: `StrawWU-0.4.1.33-amd64.iso`（dev-iso + STRAWWU_ENABLE_E2E=1 建置）

結果 JSON: `tests/install-e2e/output/firstboot-e2e-result.json`

```json
{
  "version": "0.4.1.33",
  "status": "PASS",
  "firstboot_marker": "FIRSTBOOT_OK",
  "install_ok": true,
  "boot_ok": true,
  "firstboot_ok": true
}
```

Serial 證據: `tests/install-e2e/output/logs/firstboot-e2e-installed.log` 含 `FIRSTBOOT_OK`（L789–790）

### `make preflight` — exit 0（~218s）

Log: `/tmp/w6-n5-preflight-final.log`

含 W0–W5 全部階段 + **W6-N5 install-firstboot-e2e**（`=== W6-N5 install-firstboot-e2e done: PASS ===`）

### `make test-install-firstboot-e2e-static` — exit 0（~26s）

Log: `/tmp/w6-n5-static.log`

## 治本修復紀錄

| 根因 | 修復 |
|------|------|
| `/dev/fd/63` mapfile 在部分 shell 不可用 | `load_qemu_disk_args()` 陣列載入 |
| `validate-partition-probe` 誤依賴 `dev-iso-e2e`（sudo pty） | Makefile 改為僅跑 partition-probe |
| `localecfg` → `locale-gen` 在 QEMU 無限 hang | `shellprocess_e2e-locale` 僅 en_US.UTF-8 |
| `bootloader_e2e` 180s timeout（initramfs 慢） | timeout 900s |
| systemd ordering cycle 跳過 firstboot 服務 | boot-marker Before=multi-user；firstboot After=multi-user（無 Wants cycle） |
| 舊 ISO 缺 xdotool / 新 firstboot | dev-iso E2E rebuild + 9p overlay |

## 已知限制

| 項目 | 狀態 |
|------|------|
| 完整 E2E 耗時 ~40–45 分（rsync squashfs + initramfs） | 環境正常；可調高 `STRAWWU_INSTALL_E2E_TIMEOUT` |
| GTK4 實機精靈 UI | E2E 用 `--e2e` headless；GTK 路徑仍由 W5-N3 單元/preflight 覆蓋 |
| release-iso Phase 驗收 | 本 worker 用 dev-iso E2E ISO；release 驗收留待 Hermes trigger |
| `make test-install-firstboot-e2e` 首次需 dev-iso-e2e ISO | 已產出 `StrawWU-0.4.1.33-amd64.iso` |

## VERSION

`0.4.1.32` → `0.4.1.33`（iterate）

## 建議 commit message

```
feat(w6): install + firstboot E2E with serial FIRSTBOOT_OK

- strawwu-firstboot --e2e headless mode + lifecycle.firstboot=done
- run-firstboot-e2e.sh: Calamares install → installed boot → FIRSTBOOT_OK
- fix E2E locale-gen hang, bootloader timeout, systemd ordering cycle
- load_qemu_disk_args for shells without process substitution
Tests: make preflight PASS, firstboot-e2e-result PASS (0.4.1.33)
Version: 0.4.1.33
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T10:59:00-0400 | `[worker-START]` w6-n5-install-e2e |
| 2026-07-05T15:26:47-0400 | `[worker-DONE]` firstboot-e2e-result PASS + preflight PASS — 待 Hermes mark |

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
export STRAWWU_ISO_PATH=os-image/output/StrawWU-0.4.1.33-amd64.iso
make test-install-firstboot-e2e
make preflight
```

## 下一階段

**w6-i4-installed-boot**（Hermes mark PASS 後自動啟動，勿問使用者）。
