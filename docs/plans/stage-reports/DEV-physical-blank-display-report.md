# DEV: 實體開機無畫面 / 沒系統 — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 | post-hw-t1-live-usb（boot bug） |
| 任務書 | docs/plans/kickoff/DEV-physical-blank-display.md |
| 觸發 | 使用者回報實體機開機無畫面（2026-07-08）；0.7.0.13/0.7.0.14 仍 FAIL；0.7.0.14 Live USB「進 GRUB 選開機項後掉回韌體＝沒系統」（2026-07-09） |
| 版本 | `0.7.0.26` |
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
| ISO 版本 | 請刷 `StrawWU-0.7.0.26-amd64.iso`（0.7.0.25 曾回歸缺 GRUB fallback，勿用） |
| 使用者驗證 | **待刷 0.7.0.26 回報**；QEMU BIOS + SecureBoot 皆 PASS（2026-07-10、**2026-07-11 重跑確認**） |
| 截圖/錄影 | 無 |

## 結論

治本：根因為 **Secure Boot 拒絕未簽章自製核心**（非先前推測的 GPU/KMS 黑屏）。0.7.0.17 導入 hybrid：MOK 簽自製核心 + 未 enroll 時自動 fallback 到 Canonical 簽章 generic 核心。

**0.7.0.25 回歸（2026-07-10）**：`build-iso.sh` 在 `sync_casper_kernel`（stage vmlinuz-generic）**之前**就執行 `patch-iso-secureboot-fallback.sh`，patch 因 fallback 檔尚未存在而 skip → 實機 UEFI+Secure Boot 又會「選 GRUB 後掉回韌體」。**0.7.0.26** 修正 build 順序（patch 改在 sync_casper_kernel 之後）。

| 版本 | GRUB fallback | QEMU BIOS | QEMU SecureBoot |
|------|---------------|-----------|-----------------|
| 0.7.0.17 | ✅ | PASS | PASS |
| 0.7.0.25 | ❌ 回歸 | 未重測 | 未重測 |
| 0.7.0.26 | ✅ | PASS (217s, 07-11) | PASS (227s, 07-11) |

**勿自行宣稱 stage PASS**；由 Hermes/使用者刷實機後 mark。

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

## 自製部分全面審查修正 (aall, v0.7.0.21)

依使用者「完整詳細審查自製 part」+「aall」，對自製程式碼做全面治本修正（非表面）。全部經 `make test-phase0` + `make preflight` 通過（0 FAIL）。

### Rust 元件（治本安全性/正確性）
- launcher：缺檔/非法二進位不再偽造成功；PE stub 合成改由 `STRAWWU_SMOKE=1` 顯式開啟；成功訊息標 `mode=simulated`。
- strawwu-nt：`loader.rs`/`pe.rs` RVA/size 計算改 u64，杜絕 u32 溢位回繞。
- app-registry：原子寫入（temp+rename）+ 跨程序 `flock` 諮詢鎖（有界重試逾時）；log 改 `serde_json` 防注入。
- launcher desktop entry：app-id 白名單驗證（防路徑穿越）+ 值跳脫（防換行注入）。
- flatpak/apt 移除：app-id/套件名驗證 + `--` 終止選項（防引數注入）。

### OS image 建置管線
- `clone-ubuntu-base.sh`：修 `dpkg-query` 引號 bug；新增 base ISO SHA256 校驗（來源 target JSON/env/上游 SHA256SUMS）。
- Secure Boot 統一為 **MOK 單軌**（shim/grub 維持 Canonical 簽章，僅核心 MOK 簽）；`patch_boot_serial_console` 修正避免誤改 `vmlinuz-generic`；fallback grub patch 僅在確有 staged fallback 時套用。
- branding sed 由全域替換收斂為僅改 menuentry/submenu 標題與已知字串（避免破壞 `search --label` 開機媒體偵測與 gnome-shell）。
- 為會改系統/他人檔的 deb 補 `prerm`/`postrm`（laptop/device-proxy/icon-theme）。

### Kernel pin（單一真相來源）
- ABI 單一來源＝`docs/plans/ubuntu-base-target.json` `active.kernel_abi`；移除 Makefile/腳本硬編字面 fallback。
- `apt-get source` 移除未 pin fallback → 版本不符即硬失敗；抓取後驗證樹版本符合 ABI。
- 產出 `.kernel-signing` 誠實記錄簽核姿態（module sig 關閉、vmlinuz 交由 ISO 階段 MOK 簽）；`swap-kernel.sh` 記錄實際 MOK 簽核結果。

### Electron Hub
- `sandbox:true` + 導航守衛（will-navigate/setWindowOpenHandler）+ IPC 引數驗證 + `escapeHtml` 補跳脫引號（防屬性逸出 XSS）。

### 測試誠實 / Git 衛生
- 無 rootfs 環境的 preflight 由假 PASS 改回報 **SKIPPED**；CI 補齊 `lrelease` 等相依；Rust CLI 修 SIGPIPE panic。
- 止血 repo 膨脹：取消追蹤 389 個 `os-image/debs/*/output/*.deb` 與 `tests/apt-repo|ci/output/`（含測試用 GPG 私鑰）並加入 `.gitignore`；歷史瘦身（filter-repo + force-push main）屬破壞性，待使用者明示授權再執行。

### README 漂移同步
- 版本 0.4.0.0→0.7.0.21、kernel 6.8.12→7.0.0-strawwu(6.14+)、codename noble→resolute(26.04)、Rust crate 8→11（補 app-registry/cli/hub）。
