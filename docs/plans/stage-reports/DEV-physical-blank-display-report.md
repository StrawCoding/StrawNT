# DEV: 實體開機無畫面 / 沒系統 — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 | post-hw-t1-live-usb（boot bug） |
| 任務書 | docs/plans/kickoff/DEV-physical-blank-display.md |
| 觸發 | 使用者回報實體機開機無畫面（2026-07-08）；0.7.0.13/0.7.0.14 仍 FAIL；0.7.0.14 Live USB「進 GRUB 選開機項後掉回韌體＝沒系統」（2026-07-09） |
| 版本 | `0.7.0.17` |
| official-release | 已停止（未授權） |

## 回報演進

1. 初期：實體機開機螢幕長黑（無 Plymouth/桌面）→ 當作 GPU/KMS 顯示問題處理（0.7.0.12~14 修 early2 GPU 模組/firmware/hook）。
2. 2026-07-09：0.7.0.14 Live USB 實機**進得到 GRUB 選單，但選開機項後掉回韌體/黑屏＝沒系統**。這與「有開機但黑屏」不同 —— 失敗發生在 **GRUB 交棒核心**、根本還沒到顯示階段。

## 根因（治本，已用 QEMU Secure Boot 重現）

**StrawWU 把 Ubuntu 的 Canonical 簽章核心換成自製 `linux-image-strawwu`，但自製核心完全未簽章。** 實機 UEFI 預設開 Secure Boot 時：

- `EFI/boot/bootx64.efi`（shim）→ Microsoft UEFI CA 簽章，載入成功。
- `EFI/boot/grubx64.efi` → Canonical Secure Boot 簽章，載入成功（∴ GRUB 選單出得來）。
- `casper/vmlinuz`（自製核心）→ **`No signature table present`（未簽章）** → shim 驗章失敗 → `error: bad shim lock signature` → **掉回韌體＝沒系統**。

之前 QEMU boot-test 用**非 Secure Boot 的 OVMF**（`OVMF_CODE_4M.fd` + 預設 VARS），所以永遠測不到這條路徑，才會一路 PASS 卻與實機不符。

### 根因重現（0.7.0.14，QEMU Secure Boot，MS+Canonical CA enrolled）
serial 明確輸出：
```
error: bad shim lock signature.
error: you need to load the kernel first.
Failed to boot both default and fallback entries.
```
= 與實機「進 GRUB 選了掉回韌體」完全一致。

## 修復（v0.7.0.17）— Hybrid：MOK 簽自製核心 + 未 enroll 時 fallback 到簽章核心

| 檔案 | 變更 |
|------|------|
| `os-image/scripts/secureboot-route/generate-mok.sh` | 產生/持久化 StrawWU MOK（RSA-2048，`os-image/keys/secureboot/`），簽章跨版本穩定，使用者只需 enroll 一次 |
| `os-image/scripts/secureboot-route/mok-sign.sh` | 冪等 sbsign 簽核心（已簽則跳過；無金鑰則安全 no-op） |
| `os-image/scripts/swap-kernel.sh` | 安裝自製核心後用 MOK 簽章；保護 Canonical 簽章 generic 核心不被 autoremove（fallback 依賴） |
| `os-image/scripts/build-iso.sh` | `sync_casper_kernel` 簽 `casper/vmlinuz`；`stage_secureboot_fallback_kernel` 佈署 `casper/vmlinuz-generic`（Canonical 簽）+ `casper/initrd-generic`（上游原生 casper initrd）；`install_secureboot_assets` 佈署 MOK 憑證 + enroll 工具進 rootfs；接入 grub fallback patch |
| `os-image/scripts/patch-iso-secureboot-fallback.sh` | 重寫每個 menuentry：先試 MOK 簽自製核心，`$?`≠0（Secure Boot 拒未 enroll MOK）→ 自動 fallback 到 `/casper/vmlinuz-generic` + `/casper/initrd-generic` |
| `os-image/config/secureboot/strawwu-mok-enroll` | 使用者 enroll MOK 的工具（`mokutil --import`；SB 關/已 enroll 時安全 no-op），用於啟用自製效能核心 |
| `tests/boot/run.sh` | 新增 `secureboot` boot-test 模式（`OVMF_CODE_4M.secboot.fd` + `OVMF_VARS_4M.ms.fd`，smm=on，secure=on） |
| `tests/preflight/test-iso-before-boot.sh` | 新增 SB hybrid 閘門：casper/vmlinuz 為 MOK 簽、casper/vmlinuz-generic 為 Canonical 簽、initrd-generic 存在、grub 有 fallback；修正 vmlinuz glob 不被 -generic 遮蔽 |
| `Makefile` | `boot-test-dev-iso`=bios,secureboot；`boot-test-release-iso`=bios,uefi,secureboot；新增 `boot-test-secureboot` |

### 開機決策矩陣（治本）
| 情境 | 結果 |
|------|------|
| Secure Boot 關 | 開自製效能核心（完整功能） |
| Secure Boot 開 + 已 enroll MOK | 開自製效能核心 |
| Secure Boot 開 + 未 enroll MOK | **自動 fallback 到 Canonical 簽章 generic 核心 → 開機到桌面（不再沒系統）** |

## 驗證（本階段實測，dev-iso 0.7.0.17）

| 命令 | 結果 | 備註 |
|------|------|------|
| `test-iso-before-boot.sh`（dev-iso） | **exit 0，零 FAIL** | SB hybrid 檢查全 PASS |
| BIOS boot-test | **PASS**（226s） | STRAWWU_BOOT_OK |
| **SecureBoot boot-test** | **PASS**（239s） | 見下方 serial 證據 |
| `boot-result.json` 頂層 status | **PASS** | modes: bios,secureboot |

### ISO 簽章鏈驗證（`StrawWU-0.7.0.17-amd64.iso`）
| 項目 | 結果 |
|------|------|
| `casper/vmlinuz` | **StrawWU MOK 簽章**（sbverify OK） |
| `casper/vmlinuz-generic` | **Canonical 簽章**（fallback） |
| `casper/initrd-generic` | 存在（上游原生 casper initrd，95MB） |
| `boot/grub/grub.cfg` | 3 個 menuentry 皆有 custom→generic fallback |

### SecureBoot serial 證據（fallback 生效）
```
error: bad shim lock signature.
StrawWU: Secure Boot without enrolled MOK - booting signed fallback kernel
...
STRAWWU_BOOT_OK
```
即：Secure Boot 拒絕未 enroll 的自製核心後，**自動 fallback 到 Canonical 簽章 generic 核心並開到 GDM 桌面** —— 徹底解決「沒系統」。

## 實體機證據

| 項目 | 值 |
|------|-----|
| 機型 | 待填（使用者未提供） |
| BIOS/UEFI | UEFI + Secure Boot（實機回報掉回韌體＝已用 QEMU Secure Boot 重現+修復驗證） |
| 啟動媒體 | Live USB（內建螢幕） |
| ISO 版本 | 請刷 `StrawWU-0.7.0.17-amd64.iso` |
| 使用者驗證 | **待刷 0.7.0.17 回報**；QEMU BIOS + SecureBoot 皆 PASS |
| 截圖/錄影 | 無 |

## 結論

治本：根因為 **Secure Boot 拒絕未簽章自製核心**（非先前推測的 GPU/KMS 黑屏）。0.7.0.17 導入 hybrid：MOK 簽自製核心 + 未 enroll 時自動 fallback 到 Canonical 簽章 generic 核心。QEMU BIOS **PASS**（226s）+ **SecureBoot PASS**（239s，serial 證實走 fallback 開到桌面）。並新增 Secure Boot QEMU boot-test 進回歸閘門（先前正因 boot-test 沒測 Secure Boot 才漏掉）。**勿自行宣稱 stage PASS**；由 Hermes/使用者刷實機後 mark。

## 建議 commit message
```
fix(iso): Secure Boot hybrid — MOK-sign custom kernel + signed generic fallback (0.7.0.17)

Root cause: unsigned custom linux-image-strawwu is rejected by shim under UEFI
Secure Boot ("bad shim lock signature") -> drops to firmware = "no system".
QEMU boot-test never enabled Secure Boot so it was missed.

- MOK: generate/persist StrawWU MOK; sbsign custom kernel (idempotent)
- casper: stage Canonical-signed vmlinuz-generic + upstream initrd-generic
- grub: try MOK-signed custom kernel, fall back to signed generic on shim reject
- rootfs: ship MOK cert + strawwu-mok-enroll; keep signed generic kernel
- tests: add secureboot QEMU boot-test mode + preflight SB gate
Verified: BIOS PASS (226s), SecureBoot PASS (239s, fallback -> desktop)
Issue: v0.7.0.14 physical Live USB "no system" (Secure Boot)
```
