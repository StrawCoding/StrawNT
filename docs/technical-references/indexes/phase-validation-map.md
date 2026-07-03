# Phase × 上游文件 × 驗證對照表

StrawWU v3.0-cleanroom · noble 24.04 · 更新 2026-07-03

## 圖例

- **規劃**：設計/實作前必讀
- **驗證**：PASS/FAIL 判斷依據（StrawWU 測試優先）
- **稽核**：疑難雜症時對照上游原始碼

---

## Phase 0 — 骨架

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| 禁 legacy | — | 規劃 | `make preflight` / `tests/preflight/test-ubuntu-clone.sh` |
| 目錄規範 | `docs/architecture.md` | 規劃 | 檔案樹存在 |

---

## Phase 1 — Ubuntu clone + ISO

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| casper 目錄佈局 | `upstream/casper-1.498/scripts/`、`manpages/casper.7.html` | 規劃 | ISO 內 `/casper/minimal*.squashfs` |
| xorriso El Torito | `upstream/guides/xorriso/`、`libisoburn-1.5.6/doc/` | 規劃+稽核 | 禁止 `-map` 整碟；增量 repack |
| squashfs 分層 | casper manpage `overlayfs-path` | 稽核 | 只重打 `minimal.squashfs` |
| GRUB live 參數 | `upstream/grub2-2.12/`、`manpages/local/grub-install.txt` | 規劃 | `boot=casper`、`console=tty0 console=ttyS0` |
| QEMU harness | — | 驗證 | `make boot-test-release-iso` → `STRAWWU_BOOT_OK` |

**關鍵上游檔**
- `casper-1.498/hooks/` — initramfs 掛載邏輯
- `guides/ubuntu_livecd_customization.html` — 社群 ISO 客製流程

---

## Phase 2 — 自訂 kernel + initrd

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| kbuild / bindeb-pkg | `linux-v6.8.12/Documentation/kbuild/` | 規劃 | `make -C kernel build` → `.deb` |
| OVERLAY_FS builtin | `Documentation/filesystems/overlayfs.rst` | 稽核 | initrd overlay 不 panic |
| ISO9660 builtin | `Documentation/filesystems/isofs.rst` | 稽核 | casper 讀 CD 模組 |
| initramfs 結構 | `initramfs-tools-0.142ubuntu25.8/docs/`、`hooks/` | 規劃+稽核 | early3 模組版本 = strawwu |
| initrd splice | casper hooks + initramfs `scripts/` | 稽核 | 保留 upstream `main.zst` |
| Plymouth in main | `plymouth-24.004.60/docs/`、`themes/` | 規劃 | plymouthd 在 main 段 |
| casper 掛載時序 | `casper-1.498/scripts/casper-premount/`（對照） | 稽核 | `05strawwu-wait-live-media` |
| ISO 三模式 | `docs/iso-modes.md` | 驗證 | release-iso 禁 SKIP_SQUASHFS |
| preflight 閘門 | — | 驗證 | `make preflight-iso-before-boot` |
| boot-test | — | 驗證 | `boot-result.json` 頂層 `status=PASS` |

**關鍵上游檔**
- `initramfs-tools-0.142ubuntu25.8/scripts/initramfs-tools`
- `casper-1.498/scripts/casper`（live 媒體掃描）
- `plymouth-24.004.60/src/` — initramfs hook

**QEMU 注意（StrawWU 實測）**
- UEFI：virtio-scsi + scsi-cd（q35+ich9-ahci 無 `/dev/sr0`）
- BIOS：serial `STRAWWU_BOOT_OK` ×2

---

## Phase 3 — Calamares E2E

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| Ubuntu settings | `calamares-settings-ubuntu-24.04.40/common/etc/calamares/` | 規劃+稽核 | 僅 branding 差異 |
| partition.conf | 同上 `partition.conf` | 稽核 | `devices.type: any` |
| settings 模組順序 | 同上 `settings.conf` | 稽核 | 必有 `exec:` phase |
| Calamares API | `git-calamares/man/`、`src/libcalamares/` | 規劃 | 不自造 devices.conf |
| 啟動方式 | Ubuntu desktop entry | 驗證 | `sudo -E calamares` |
| E2E | — | 驗證 | `make test-install-e2e` |

**禁止清單**：見 skill `calamares-sop.md`（曾浪費 9h+ 項目）

---

## Phase 4–6 — Greenfield / Hub / Win compat

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| Kernel driver API | `linux-v6.8.12/Documentation/driver-api/` | 規劃 | strawwu_ipc、device-proxy |
| 裝置列舉 | `Documentation/admin-guide/` | 規劃 | udev 代理規格 |
| Electron Hub | — | 規劃 | Phase 5 獨立規格 |
| Win32 相容 | — | 規劃 | `components/specs/` |

---

## Phase 7 — Release

| 主題 | 上游參考 | 類型 | StrawWU 驗證 |
|------|----------|------|--------------|
| ISO 完整性 | xorriso + SHA256 | 驗證 | `sha256sum -c` |
| 雙韌體開機 | grub2 + casper | 驗證 | BIOS+UEFI boot-test |
| 交付 | — | 驗證 | HTML hermes-deliver |

---

## 常用對照命令

```bash
# 比對 Calamares 上游
diff -ru upstream/calamares-settings-ubuntu-24.04.40/common/etc/calamares/ \
  os-image/work/chroot/etc/calamares/ | head

# 讀 casper premount 邏輯
grep -r live-media upstream/casper-1.498/scripts/ | head

# initramfs hook 列表
ls upstream/initramfs-tools-0.142ubuntu25.8/hooks/

# kernel overlay 文件
sed -n '1,80p' upstream/linux-v6.8.12/Documentation/filesystems/overlayfs.rst
```
