# W6-HW1 實機 Live USB 階段報告

| 任務 | w6-hw1-live-usb |
|------|-----------------|
| 版本 | 0.4.1.39 |
| 日期 | 2026-07-05 |
| Worker | 階段 36/47（w6-hw1-live-usb） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

≥3 台 Live USB 開機 PASS，對齊 `strawwu-hardware-compatibility-test-matrix.md` T1 分級。

## 交付物

| 類型 | 路徑 |
|------|------|
| HW 共用函式庫 | `tests/hw/lib.sh` |
| Live smoke（實機/dev-vm 用） | `tests/hw/smoke-live.sh` |
| QEMU 矩陣 runner | `tests/hw/run-live-usb-matrix.sh` |
| Preflight gate | `tests/preflight/test-hw-live-usb.sh` |
| 矩陣結果 | `docs/plans/hw-matrix-results.json` |
| baseline JSON | `docs/plans/baselines/hw-live-usb-baseline.json` |
| Makefile | `test-hw-live-usb`；`preflight` 含本階段 |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **smoke-live.sh** | 在已開機 Live 環境偵測 CPU/GPU/firmware，檢查 session、網路、音效、StrawWU branding |
| **run-live-usb-matrix.sh** | 三種 QEMU profile 從 ISO 開機，serial 偵測 `STRAWWU_BOOT_OK` + `STRAWWU-DESKTOP-OK` |
| **hw-matrix-results.json** | 結構化記錄每台 machine_id、tests、markers、serial log 路徑 |
| **preflight** | 驗證腳本存在、JSON schema、≥3 live_boot PASS |

### 三種 QEMU proxy profile（T1 CI 代理）

| machine_id | firmware | 用途 |
|------------|----------|------|
| hw-proxy-pc-bios | Legacy BIOS (pc/i440fx) | 舊韌體 / Legacy 開機 |
| hw-proxy-q35-uefi | UEFI (q35 4-core) | 現代筆電級 UEFI |
| hw-proxy-q35-uefi-smp8 | UEFI (q35 8-core) | 桌機級 UEFI |

## 驗收命令輸出（2026-07-05 22:52–23:03 UTC-4，worker 終驗）

### `make test-hw-live-usb` — exit 0（~591s）

Log: `/tmp/w6-hw1-test-hw-live-usb.log`

```
PASS: hw-matrix-results.json written (3/3 live PASS)
=== W6-HW1 hw-live-usb done: PASS ===
```

| Profile | live_boot | desktop | 耗時 |
|---------|-----------|---------|------|
| hw-proxy-pc-bios | PASS | PASS | 211s |
| hw-proxy-q35-uefi | PASS | PASS | 188s |
| hw-proxy-q35-uefi-smp8 | PASS | PASS | 191s |

ISO: `StrawWU-0.4.1.33-amd64.iso`（`STRAWWU_ISO_PATH` 指定；VERSION 0.4.1.39 尚無對應 ISO）

### `make preflight` — exit 0（~222s）

Log: `/tmp/w6-hw1-preflight.log`

含 W0–W6-W6 全部階段 + **W6-HW1 hw-live-usb** 全部 exit 0（終行：`=== W6-HW1 hw-live-usb done: PASS ===`）。

## 變更檔案清單

```
VERSION (0.4.1.38 → 0.4.1.39)
Makefile
tests/hw/lib.sh                                              (新增)
tests/hw/smoke-live.sh                                       (新增)
tests/hw/run-live-usb-matrix.sh                              (新增)
tests/preflight/test-hw-live-usb.sh                          (新增)
docs/plans/hw-matrix-results.json                            (新增)
docs/plans/baselines/hw-live-usb-baseline.json               (新增)
docs/plans/stage-reports/W6-HW1-live-usb-report.md           (本檔)
```

## 技術備註（治本）

1. **HW0+HW1 合併交付**：依矩陣計畫 HW0（模板+腳本）與 HW1（≥3 Live PASS）一次完成，避免空跑 preflight。
2. **雙路徑設計**：CI 用 QEMU proxy 自動化；實機用 `smoke-live.sh --output entry.json` 手動合併至 `hw-matrix-results.json`（w8-hw-matrix 擴充 GPU/Wi-Fi/suspend）。
3. **boot lock 共用**：沿用 `os-image/work/.boot-test.lock`，禁止并行 boot-test 寫同一 ISO。
4. **誠實邊界**：本階段 3/3 為 **qemu-proxy** 環境；實體 USB（Rufus/dd/Ventoy）與 Intel/AMD/NVIDIA 真機驗證留待 Hermes 實機 session 或 w8-hw-matrix。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 實體 USB 三種寫入方式（Rufus/dd/Ventoy） | 待 Hermes 實機 |
| Wi-Fi / 音效 / suspend 實機 | w8-hw-matrix |
| release-iso 0.4.1.39 重建 | 建議 Hermes trigger-verify 前 build |
| smoke-live.sh 實機合併流程 | 文件化於 w6-doc1-user-docs |

## VERSION

`0.4.1.38` → `0.4.1.39`（iterate）

## 建議 commit message

```
feat(w6): Live USB hardware matrix — ≥3 machine profiles + smoke-live

- tests/hw/ runner with 3 QEMU proxy profiles (Legacy BIOS + 2× UEFI)
- smoke-live.sh for physical Live session checks
- hw-matrix-results.json + preflight gate
Tests: make test-hw-live-usb PASS, make preflight PASS
Version: 0.4.1.39
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T22:35 UTC-4 | `[worker-START]` 階段 36/47 w6-hw1-live-usb |
| 2026-07-05T22:48 UTC-4 | `[worker-START]` Hermes companion tick — 接續階段 36/47 |
| 2026-07-05T23:03 UTC-4 | `[worker-DONE]` 終驗：`make test-hw-live-usb` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w6-doc1-user-docs**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 續跑狀態

無阻塞。若需重跑矩陣：

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
STRAWWU_ISO_PATH=os-image/output/StrawWU-<ver>-amd64.iso make test-hw-live-usb
make preflight
```

Serial 證據：`tests/hw/output/serial-hw-proxy-*.log`
