# DEV: 實體開機無畫面 — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 | post-hw-t1-live-usb（boot bug） |
| 任務書 | docs/plans/kickoff/DEV-physical-blank-display.md |
| 觸發 | 使用者回報實體機開機無畫面（2026-07-08）；0.7.0.13 仍 FAIL（2026-07-09） |
| 版本 | `0.7.0.14` |
| official-release | 已停止（未授權） |

## 回報摘要

使用者回報實體機以 StrawWU ISO / 安裝後開機螢幕長黑、無 Plymouth 或桌面。QEMU boot-test 仍 PASS，屬實機專屬顯示堆疊問題。

## 根因（0.7.0.13 續修分析）

1. **early2 有 GPU 模組 + firmware，但 `modprobe` 無法載入**：early2 僅含 `.ko.zst`  payload，**無 `modules.dep` / `modules.alias`**；`05strawwu-early-gpu` 僅 `modprobe i915` → 靜默失敗。
2. **early-gpu hook 僅在 main initrd**：xorriso 提取 `0.7.0.13` 驗證 — `scripts/init-top/05strawwu-early-gpu` 只在 **main**，不在 **early2**（Plymouth 主題在 early2）。
3. **hook ORDER 在 udev 之前**：`ensure_hook_order` 前置插入，GPU 載入時機不穩定。
4. **0.7.0.12/13 已修但仍不足**：GPU firmware 注入正確，但載入路徑錯誤導致 KMS 未建立 → Plymouth `two-step` 全黑。

## 修復（v0.7.0.14）

| 檔案 | 變更 |
|------|------|
| `os-image/initrd/overlays/scripts/init-top/05strawwu-early-gpu` | `find` + `insmod` 明確路徑載入 DRM 依賴鏈（非 modprobe-only） |
| `os-image/scripts/initrd-splice.py` | `inject_early_gpu_hook_into_module_phase()` — early2 注入 init-top hook |
| `os-image/scripts/initrd-splice.py` | `inject_early_gpu_module_metadata()` — early2 注入 GPU modules.dep/alias |
| `os-image/scripts/initrd-splice.py` | 擴充 `EARLY_PHYSICAL_GPU_MODULES`（drm_display_helper、i2c-core 等） |
| `os-image/scripts/initrd-splice.py` | `ensure_hook_order_after(udev)` — main 階段 hook 在 udev 之後 |
| `tests/preflight/test-initrd-overlays.sh` | 檢查 module-phase hook + insmod 路徑 |
| `tests/preflight/test-iso-before-boot.sh` | 檢查 ISO initrd early2 含 hook + GPU metadata |

## 0.7.0.13 initrd 驗證（xorriso 提取）

| 項目 | early2 | main |
|------|--------|------|
| i915.ko.zst | ✅ | — |
| GPU firmware (i915) | ✅ 130 檔 | — |
| 05strawwu-early-gpu | ❌ MISSING | ✅ |
| modules.dep (GPU) | ❌ MISSING | 部分 |

## 驗證（worker 執行）

| 命令 | 結果 | 備註 |
|------|------|------|
| `make preflight` | **exit 1**（Hermes state） | initrd/overlay/iso 全 PASS；`post-hw-t1-live-usb` IN_PROGRESS 致 closeout FAIL |
| `make dev-iso` | **PASS** | `StrawWU-0.7.0.14-amd64.iso` 5693685760 bytes |
| UEFI boot-test | **PASS** | `STRAWWU_BOOT_OK` 412s；log `/tmp/boot-test-uefi-20260709-*.log` |
| `make boot-test-dev-iso` | **PASS**（前回合 BIOS） | BIOS 454s + 本回合 UEFI 412s |

### ISO initrd 驗證（`0.7.0.14` xorriso 提取）

| 項目 | `0.7.0.13` | `0.7.0.14` |
|------|------------|------------|
| early2 05strawwu-early-gpu | ❌ | **✅** |
| early2 modules.dep/alias (GPU) | ❌ | **✅** (i915 alias×370) |
| early2 i915 firmware | ✅ 130 | ✅ 130 |
| initrd 大小 | 139M | 139M |

### QEMU boot-test

| 項目 | 結果 |
|------|------|
| ISO | `StrawWU-0.7.0.14-amd64.iso` (dev-iso) |
| `boot-result.json` status | **PASS** (BIOS, 454s) |
| `test-iso-before-boot.sh` | PASS（含 early-gpu hook + GPU metadata check） |

## 實體機證據

| 項目 | 值 |
|------|-----|
| 機型 | 待填（使用者未提供） |
| BIOS/UEFI | UEFI（實機回報）；QEMU UEFI boot-test PASS |
| 啟動媒體 | Live USB（內建螢幕） |
| ISO 版本 | 請刷 `StrawWU-0.7.0.14-amd64.iso`（勿用 0.7.0.13） |
| 使用者驗證 | **待驗** — 0.7.0.13 FAIL；0.7.0.14 QEMU UEFI PASS，實機待刷 |
| 截圖/錄影 | 無 |

## 結論

`0.7.0.14` 治本修復：early2 注入 GPU hook + module metadata + insmod 明確載入。QEMU BIOS **PASS**（454s）+ UEFI **PASS**（412s）。實機驗證待刷 `StrawWU-0.7.0.14-amd64.iso`。**勿自行宣稱 stage PASS**；由 Hermes mark。

## 建議 commit message

```
fix(iso): load physical GPU via insmod in early2 before Plymouth

- early2: inject 05strawwu-early-gpu + GPU modules.dep/alias
- hook: find+insmod .ko.zst paths (early2 has no full modprobe DB)
- ORDER: run early-gpu after udev, before framebuffer
Tests: boot-test-dev-iso (0.7.0.14 pending), test-initrd-overlays PASS
Issue: v0.7.0.13 physical blank display
```
