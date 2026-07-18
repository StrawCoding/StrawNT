# POST-HW-T1-live-usb — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-hw-t1-live-usb` |
| 版本 | `0.7.1.7` |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS）；前次 0.7.1.6 實機仍黑畫面 → 本回合治本 |
| 完成時間 | 2026-07-19T07:30+08:00 |
| Worker 回合 | Cursor 階段 1/8（治本：`plymouth.ignore-serial-consoles`） |

## 摘要

POST-HW-T1：≥3 台 `physical-live`；`gpu_driver` / `wifi` 須 **PASS**（非 SKIP／FAIL）。

Hermes inbox（2026-07-19 07:02）：**0.7.1.6 刷機後實機仍黑畫面**。不可因 QEMU PASS 收工。

### 真正根因（治本）

為了 QEMU boot-test 序列標記，GRUB 一律帶 `console=ttyS0,115200n8`。  
**Plymouth 偵測到序列主控台後會綁定 serial seat，實體面板（HDMI/筆電螢幕）保持全黑。**  
QEMU 用 `-display none` + 讀 `ttyS0` 上的 `STRAWWU_BOOT_OK`，因此一直假 PASS；實機使用者只看到黑畫面。這也解釋為何「改預設 generic kernel」（0.7.1.6）仍無法解決。

次要強化（同 ISO）：

- Live overlay：`DeviceTimeout=30`、補 `/usr/share/gnome-shell/theme/StrawWU-Dark/`（mode `stylesheetName` 路徑）、`casper.conf` 釘 `FLAVOUR=StrawWU`
- 預設仍走 Canonical `vmlinuz-generic`（0.7.1.6 政策保留）

## Hermes 介入

| 時間 | 內容 | 處置 |
|------|------|------|
| 07-19 07:02 | FAIL — 0.7.1.6 實機黑畫面重複 | `plymouth.ignore-serial-consoles` + overlay 顯示修復 → **0.7.1.7** |

## 根因對照

| 情境 | ≤0.7.1.6 | 0.7.1.7 |
|------|----------|---------|
| GRUB + `console=ttyS0` | Plymouth 綁 serial → **實機面板黑** | 同參數 + **`plymouth.ignore-serial-consoles`** → 畫面走 tty0/DRM |
| QEMU boot-test | serial marker PASS（掩蓋實機問題） | 仍可讀 serial；面板路徑亦正確 |
| Live 預設核心 | generic（0.7.1.6） | 不變 |
| Plymouth DeviceTimeout | rootfs 仍 8s | live overlay **30s** |
| Shell mode CSS | `stylesheetName` 指向不存在路徑 | live overlay 補齊 theme 檔 |

## 變更檔案

| 檔案 | 變更 |
|------|------|
| `os-image/scripts/build-iso.sh` | console 參數加入 `plymouth.ignore-serial-consoles` |
| `os-image/scripts/patch-iso-secureboot-fallback.sh` | 寫入/冪等檢查 ignore-serial；註解更新根因 |
| `tests/preflight/test-iso-before-boot.sh` | 閘門：有 ttyS0 必須有 ignore-serial |
| `os-image/debs/strawwu-gtk-theme/build-deb.sh` | 同步安裝 gnome-shell theme 路徑 |
| `os-image/config/branding/etc/casper.conf` | 釘 `FLAVOUR=StrawWU` |
| `os-image/config/branding/etc/plymouth/plymouthd.conf` | DeviceTimeout=30（既有） |
| `VERSION` | `0.7.1.6` → `0.7.1.7` |

## 交付物

| 類型 | 路徑 |
|------|------|
| 刷機 ISO | `os-image/output/StrawWU-0.7.1.7-amd64.iso`（SHA256 `cb4ad00a…`） |
| boot 證據 | `tests/boot/output/boot-result.json`（0.7.1.7 bios+uefi+secureboot PASS） |
| T1 矩陣 | `docs/plans/hw-matrix-results.json`（0.7.1.7，t1_physical=3；**實機面板仍待刷機**） |
| Gate | `tests/preflight/test-hw-t1-live-usb.sh` |

## 驗證（worker 局部）

### `test-iso-before-boot` — exit 0

含：`plymouth.ignore-serial-consoles`、預設 Try/Install=`vmlinuz-generic`、live 無 snap bootstrap。

Log: `/tmp/iso-before-boot-717.log`

### `tests/boot/run.sh`（`STRAWWU_BOOT_TEST_MODES=bios,uefi,secureboot`）— exit 0

| mode | status | elapsed |
|------|--------|---------|
| bios | PASS | 88s |
| uefi | PASS | 80s |
| secureboot | PASS | 79s |

Log: `/tmp/boot-test-717-full.log`

### `make test-hw-t1-live-usb` / preflight gate — exit 0

QEMU proxy 三 profile 已刷新至 0.7.1.7（誠實註記：實機面板確認前不可 mark PASS）。

### 單元測試

- `strawwu-shell/tests/test-shell.py` — PASS
- `strawwu-gtk-theme/tests/test-gtk-theme.py` — PASS

### 完整 `make preflight` / `make test-hw-t1-live-usb`

**建議 Hermes `trigger-verify`**（worker 不以此自結案）。

## 誠實邊界

1. **必須刷 0.7.1.7**：0.7.1.6 仍缺 `plymouth.ignore-serial-consoles`，實機必黑。
2. Worker **無實體螢幕證據**；QEMU PASS ≠ 實機不黑。請使用者確認 GRUB 後有 Plymouth／桌面。
3. 0.7.1.7 為 staging 外科重打包（GRUB + live overlay + xorriso）。
4. Worker **不**自宣稱 stage PASS／FAIL。

## 建議 Hermes 驗收步驟

1. `make preflight` + `make test-hw-t1-live-usb`（trigger-verify）
2. 請使用者刷 **`StrawWU-0.7.1.7-amd64.iso`**（預設 Try/Install）
3. 確認不再長黑（應見 splash／桌面）
4. 實機證據前 **禁止 mark PASS**
5. 通過後 mark → 自動下一 stage

## 建議 commit message

```
fix(hw-t1): plymouth.ignore-serial-consoles for physical Live USB (0.7.1.7)

console=ttyS0 (QEMU markers) made Plymouth bind the serial seat so real
panels stayed black while boot-test still PASSed. Pair ttyS0 with
plymouth.ignore-serial-consoles; raise DeviceTimeout; ship shell theme
CSS on the gnome-shell theme path; pin casper FLAVOUR.

Tests: iso-before-boot; boot-test bios/uefi; shell/gtk-theme units
Issue: post-hw-t1-live-usb physical blank @ 0.7.1.6
```
