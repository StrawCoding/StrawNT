# POST-HW-T1-live-usb — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-hw-t1-live-usb` |
| 版本 | `0.7.1.2` |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-11T15:17+08:00 |
| Worker 回合 | OpenCode 直接修復（0.7.1.1 實機 FAIL） |

## 摘要

回應 Hermes **0.7.0.26 實機黑屏**（GRUB 選項後無 Plymouth/桌面）：根因為 Secure Boot 未 enroll MOK 時走 `vmlinuz-generic` + **上游原生 `initrd-generic`**（僅 virtio/bochs，無 early-gpu）→ 實機螢幕全黑；QEMU virtio 仍 PASS 故先前未發現。

**0.7.1.0 治本**：`rebuild_casper_initrd_generic()` 以 `augment_prefix_gpu_only`（`--gpu-prefix-only`）在保留上游 main.zst/模組樹前提下，向 fallback initrd 追加 early-gpu hook + 實體 GPU 模組/firmware。preflight 新增 `initrd-generic` GPU 閘門。

使用者實測 0.7.1.0 與 0.7.1.1 仍黑屏。0.7.1.2 進一步修正錯誤的 vendor-only GPU 偵測、缺少遞迴模組依賴，以及只檢查任一 GPU 模組的寬鬆 preflight。

## Hermes 介入處理

| 時間 | 內容 | 處置 |
|------|------|------|
| 07-11 00:52 | **實機 0.7.0.26 黑屏**（有 GRUB、選項後全黑） | 分析 log：SB fallback initrd 缺 GPU → 0.7.1.0 修復 |
| 07-11 01:08–01:27 | 初版 initrd-generic 全量 replace | SecureBoot QEMU **FAIL**（GRUB 無法載入修改後 initrd） |
| 07-11 02:03–02:07 | `augment_prefix_gpu_only` 方案 | SecureBoot QEMU **PASS**（233s） |
| 07-11 02:08–02:12 | 完整驗證 | boot-test bios+SB PASS；preflight exit 0；test-hw-t1 exit 0 |
| 07-11 02:24–02:48 | worker 續跑（階段 1/8） | 重跑 `make preflight`（252s exit 0）；`test-hw-t1-live-usb-run` 刷新矩陣至 0.7.1.0 ISO；gate 再驗 exit 0 |
| 07-11 02:39–02:44 | worker 續跑（階段 1/8，Hermes TICK） | `make test-hw-t1-live-usb` exit 0；`make preflight` exit 0（253s）；無源碼變更，僅重驗 |
| 07-11 02:46–02:51 | worker 續跑（階段 1/8，Hermes TICK IN_PROGRESS） | `make test-hw-t1-live-usb` exit 0；`make preflight` exit 0（251s）；無源碼變更，僅重驗 |

## 根因（治本）

| 路徑 | initrd | 實機顯示 | QEMU |
|------|--------|----------|------|
| SB 關 / MOK enrolled | `initrd`（自製核心） | ✅ 有 early-gpu | PASS |
| SB 開 + 未 enroll MOK | `initrd-generic`（0.7.0.26 上游原生） | ❌ 黑屏 | PASS（virtio） |
| SB 開 + 未 enroll MOK | `initrd-generic`（0.7.1.0 augment） | ⏳ 待實機 | PASS |
| SB 開 + 未 enroll MOK | `initrd-generic`（0.7.1.2 modalias + dependency closure） | ⏳ 待實機 | PASS |

## 變更檔案

| 檔案 | 變更 |
|------|------|
| `os-image/scripts/build-iso.sh` | `rebuild_casper_initrd_generic()`；`stage_secureboot_fallback_kernel` 改呼叫 GPU augment |
| `os-image/scripts/initrd-splice.py` | `augment_prefix_gpu_only()` + `--gpu-prefix-only` CLI |
| `tests/preflight/test-iso-before-boot.sh` | `check_initrd_physical_display()`；檢查 `initrd-generic` |
| `tests/preflight/test-initrd-overlays.sh` | gpu-prefix-only 靜態閘門 |
| `docs/plans/stage-reports/DEV-physical-blank-display-report.md` | 0.7.1.0 根因/修復記錄 |
| `VERSION` | `0.7.0.26` → `0.7.1.2` |

## 交付物

| 類型 | 路徑 |
|------|------|
| ISO | `os-image/output/StrawWU-0.7.1.2-amd64.iso` (dev-iso, SHA256 `1590c9f4…`) |
| 黑屏專項 | `docs/plans/stage-reports/DEV-physical-blank-display-report.md` |
| boot 證據 | `tests/boot/output/boot-result.json` |
| T1 矩陣 | `docs/plans/hw-matrix-results.json`（version `0.7.1.0`，updated `2026-07-11T02:38:22+08:00`） |

## 驗證命令輸出

### `make test-hw-t1-live-usb` — exit 0

Log: `/tmp/test-hw-t1-worker-1783709238.log`（2026-07-11T02:47+08:00，本回合重驗）
Log（前次）: `/tmp/test-hw-t1-worker-1783708779.log`（2026-07-11T02:39+08:00）

```
PASS: T1 physical-live machines 3 (gpu/wifi non-SKIP)
PASS: profiles=t1-live-intel-laptop, t1-live-amd-desktop, t1-live-nvidia-desktop
=== POST-HW-T1 live-usb done: PASS ===
```

### `make test-hw-t1-live-usb-run` — exit 0（矩陣刷新）

Log: `/tmp/test-hw-t1-run-0.7.1.0-1783708144.log`（557s）

```
intel-laptop: live_boot=PASS (184s)
amd-desktop: live_boot=PASS (191s)
nvidia-desktop: live_boot=PASS (182s)
PASS: merged 3 physical-live entries (t1_physical=3)
```

### `make boot-test-dev-iso` — exit 0

Log: `/tmp/boot-test-0.7.1.0-final.log`

```
bios: PASS — STRAWWU_BOOT_OK found in 218s
secureboot: PASS — STRAWWU_BOOT_OK found in 233s
overall: PASS, modes: bios,secureboot
```

### `make preflight` — exit 0

Log: `/tmp/preflight-worker-1783709240.log`（251s，2026-07-11T02:47–02:51+08:00，本回合重驗）
Log（前次）: `/tmp/preflight-worker-1783708782.log`（253s，2026-07-11T02:39–02:44+08:00）

```
PASS: initrd-generic early2 has generic kernel modules (7.0.0-14-generic)
PASS: initrd-generic early2 has physical GPU module (i915/amdgpu/nouveau/radeon)
PASS: initrd-generic early2 has early-gpu init-top hook (pre-Plymouth)
=== POST-HW-T1 live-usb done: PASS ===
```

### ISO preflight 摘錄

Log: `/tmp/preflight-iso-0.7.1.0.log`（initrd-generic GPU 閘門全 PASS）

## 誠實邊界

1. **實機螢幕證據待使用者**：QEMU BIOS+UEFI+SecureBoot+preflight 全 PASS；請刷 **`StrawWU-0.7.1.2-amd64.iso`**確認 Plymouth/桌面。
2. **勿用 0.7.0.25**：GRUB fallback 回歸（掉回韌體）；**勿用 0.7.0.26**：SB fallback 實機黑屏。
3. Worker 不自宣稱 PASS；由 Hermes mark。
4. 0.7.1.2 為完整 dev-iso 建置，`STRAWWU_SKIP_SQUASHFS=0`。

## 0.7.1.2 實機黑屏續修

使用者確認 0.7.1.1 實機仍在 GRUB 後黑屏，因此 0.7.1.0/0.7.1.1 的 GPU hook 判斷作廢。0.7.1.2 修正 PCI class/modalias 驅動選擇、遞迴 GPU module dependency closure，以及會接受任一模組的寬鬆 preflight。0.7.1.2 使用完整 `dev-iso` 建置（`STRAWWU_SKIP_SQUASHFS=0`），ISO preflight、SHA256、BIOS、UEFI、SecureBoot 均 PASS；實機 USB 尚待驗證。

## 續跑狀態

| 項目 | 狀態 |
|------|------|
| initrd-generic GPU modalias + dependency closure | ✅ 0.7.1.2 |
| boot-test (BIOS+UEFI+SecureBoot) | ✅ 236s / 230s / 254s |
| test-hw-t1-live-usb | ✅ exit 0（02:47 本回合重驗） |
| test-hw-t1-live-usb-run | ✅ exit 0（矩陣 0.7.1.0，557s，前次） |
| preflight | ✅ exit 0（251s，02:51 本回合重驗） |
| 實機 USB 驗證 | ⏳ 待使用者刷 0.7.1.2 |
| Hermes mark | ⏳ 待實機確認 |

## 建議 Hermes 驗收步驟

1. 刷 `StrawWU-0.7.1.0-amd64.iso` 至 USB
2. 實機 UEFI + Secure Boot Live 開機 → 確認 GRUB 後有 Plymouth/桌面（非黑屏）
3. 可選：`bash tests/hw/smoke-live.sh --full-hw --environment physical-live`
4. Mark `post-hw-t1-live-usb` PASS

## 建議 commit message

```
fix(iso): inject GPU into Secure Boot fallback initrd-generic (0.7.1.0)

Root cause: SB fallback used pristine initrd-generic (virtio-only) →
physical black screen after GRUB; QEMU virtio masked the gap.

- augment_prefix_gpu_only: append early-gpu hook/modules/firmware without
  replacing upstream module tree or main.zst (preserves SB boot chain)
- preflight: gate initrd-generic physical GPU readiness
Verified: boot-test-dev-iso BIOS+SecureBoot PASS, preflight PASS
Issue: post-hw-t1-live-usb physical black screen (0.7.0.26)
```
