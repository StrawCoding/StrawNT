# DEV: 實體開機無畫面 — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 | post-hw-t1-live-usb（boot bug） |
| 任務書 | docs/plans/kickoff/DEV-physical-blank-display.md |
| 觸發 | 使用者回報實體機開機無畫面（2026-07-08） |
| 版本 | `0.7.0.12` |
| official-release | 已停止（未授權） |

## 回報摘要

使用者回報實體機以 StrawWU ISO / 安裝後開機螢幕長黑、無 Plymouth 或桌面。QEMU boot-test 仍 PASS，屬實機專屬顯示堆疊問題。

## 根因

1. **Casper early initrd 僅含 QEMU 虛擬 GPU 模組**（virtio-gpu、bochs、cirrus-qemu），`replace_modules_tree` 只鏡像上游已有 stem，**未注入 i915/amdgpu/nouveau/radeon**。
2. **Plymouth `two-step` 主題需 DRM/KMS**；實機 GPU 驅動未在 early 階段載入 → Plymouth 無法繪製 → `quiet splash` 下全黑。
3. **已安裝系統 GRUB** 缺少 `console=tty0`（Live ISO 已有，target-identity drop-in 未補）。

## 修復（v0.7.0.12）

| 檔案 | 變更 |
|------|------|
| `os-image/scripts/initrd-splice.py` | `EARLY_PHYSICAL_GPU_MODULES` + `inject_early_physical_gpu_modules()`（early2 注入 10 個模組） |
| `os-image/initrd/overlays/scripts/init-top/05strawwu-early-gpu` | init-top 主動 `modprobe` i915/amdgpu/nouveau/radeon |
| `os-image/debs/strawwu-target-identity/etc/default/grub.d/99-strawwu-identity.cfg` | 安裝後 GRUB 加 `console=tty0` |
| `tests/preflight/test-iso-before-boot.sh` | 檢查 early initrd 含實機 GPU 模組 |
| `tests/preflight/test-initrd-overlays.sh` | 檢查 early-gpu hook |
| `tests/preflight/test-target-identity.sh` | 檢查 grub drop-in `console=tty0` |

## QEMU boot-test

| 項目 | 結果 |
|------|------|
| ISO | `StrawWU-0.7.0.12-amd64.iso` (dev-iso) |
| `boot-result.json` status | **PASS** (BIOS, 422s) |
| initrd early2 i915/amdgpu | 已驗證存在 |
| init-top `05strawwu-early-gpu` | 已驗證存在 |
| GRUB `console=tty0` | PASS |

Log: `/tmp/boot-test-dev-iso.log`

## preflight / gate

| 命令 | exit | 備註 |
|------|------|------|
| `make test-hw-t1-live-usb` | 0 | T1 矩陣 gate PASS |
| `test-iso-before-boot.sh` | 0 | 含 physical GPU module check |
| `make preflight` | 1 | 僅 `Hermes post-hw-t1-live-usb` 狀態為 IN_PROGRESS（待 Hermes mark PASS） |

Log: `/tmp/preflight-final.log`

## 實體機證據

| 項目 | 值 |
|------|-----|
| 機型 | 待使用者 / Hermes 以 `StrawWU-0.7.0.12-amd64.iso` 刷 USB 驗證 |
| BIOS/UEFI | 待填 |
| 啟動媒體 | Live USB（建議 dev-iso 或 release-iso 重刷） |
| ISO 版本 | `0.7.0.12` |
| 截圖/錄影 | 待 Hermes 實機 session 補 |

Worker 無法代為完成實機截圖；修復已針對根因（early DRM 模組 + modprobe hook + installed console=tty0）。

## 結論

技術驗證（initrd GPU 注入、QEMU boot-test、T1 gate）已完成。**待 Hermes 實機刷 `0.7.0.12` ISO 確認螢幕有 Plymouth/桌面後 mark PASS。**

## 建議 commit message

```
fix(iso): inject physical GPU modules for Plymouth on real hardware

- early2 initrd: i915/amdgpu/nouveau/radeon + deps (10 modules)
- init-top 05strawwu-early-gpu modprobe hook
- target-identity GRUB console=tty0 for installed boot
Tests: boot-test-dev-iso PASS, test-hw-t1-live-usb PASS
Issue: v0.7.0.12
```
