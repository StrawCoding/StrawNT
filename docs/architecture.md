# StrawWU 架構（Ubuntu Clone 重啟版）

| 版本 | 2.0-reboot |
|------|------------|
| 日期 | 2026-07-02 |
| 狀態 | Phase 0 — 骨架 |

## 1. 為何重啟

舊版採 mmdebstrap 從零組 rootfs + 自訂 Calamares 設定，與 Ubuntu 上游行為脫節，導致：

- partition backend 在 QEMU 看不到 virtio/scsi 碟
- branding/settings/devices 多輪打地鼠
- E2E 假陽性浪費數小時

**治本：** 直接 clone 官方 Ubuntu noble desktop live ISO，僅做允許的差異化。

## 2. 允許的差異（白名單）

| 項目 | Ubuntu 作法 | StrawWU 允許差異 |
|------|-------------|------------------|
| Live rootfs | 官方 noble desktop ISO | 直接 unsquashfs 提取，不 debootstrap |
| Kernel | `linux-image-generic` | 替換為 `linux-image-strawwu`（自訂 .deb） |
| Calamares | `calamares-settings-ubuntu-common` | **僅** branding（logo/show.qml），不改 partition/welcome/settings |
| 桌面 | GNOME 預設 | 可加 StrawWU control-center 套件 |
| 開機 branding | Ubuntu | `/etc/os-release`、plymouth 主題（可選） |

## 3. 禁止事項

- 自造 `partition.conf` devices filter（沿用 upstream `devices.type: any`）
- 自造 `devices.conf`（Calamares 不載入）
- runtime 覆寫 `/etc/calamares`（E2E 與 live 必須一致）
- E2E 以 root 直啟 Calamares（須 `sudo -E calamares`，同 Ubuntu desktop entry）
- 跳過 preflight 直接跑 QEMU E2E

## 4. ISO 建置流程

```
1. clone-ubuntu-base.sh
   - 下載 ubuntu-24.04.x-desktop-amd64.iso（官方 mirror）
   - mount / extract casper/filesystem.squashfs → work/rootfs

2. swap-kernel.sh（chroot）
   - apt install 自訂 linux-image-strawwu_*.deb
   - apt purge linux-image-generic（保留 headers 若需 DKMS）
   - update-initramfs

3. 疊加 StrawWU 元件（chroot）
   - 安裝 components/ 產出的 .deb 或 binary
   - 僅 overlay os-image/config/branding/

4. build-iso.sh
   - mksquashfs + xorriso 重打包（參照 Ubuntu live 結構）
   - 輸出 os-image/output/StrawWU-<ver>-amd64.iso
```

## 5. Kernel 策略

Phase 1 可暫用 Ubuntu `linux-image-generic` 驗證 clone 管線，Phase 2 起替換：

- `kernel/` 目錄：基於 Ubuntu noble kernel source + StrawWU patches
- 產出 `linux-image-strawwu_<ver>_amd64.deb`
- `strawwu-kernel-bridge` 模組编入 kernel 或 loadable module

## 6. 驗證順序

```
make preflight           # 工具 + 設定靜態檢查
make clone-ubuntu-base   # rootfs 提取成功
make validate-rootfs     # 確認 calamares-settings-ubuntu-common 存在
make build-iso           # ISO 產出 + sha256
make boot-test-iso       # QEMU serial marker
make test-calamares-e2e  # 安裝 E2E（最後才跑）
```

## 7. 上游參照

```bash
# Ubuntu Calamares 設定
apt-get download calamares-settings-ubuntu-common
dpkg-deb -x calamares-settings-ubuntu-common_*.deb /tmp/ubuntu-calamares
diff -ru /tmp/ubuntu-calamares/etc/calamares os-image/config/  # 應只有 branding

# 官方 live ISO 結構
xorriso -indev ubuntu-*-desktop-amd64.iso -find / -name filesystem.squashfs
```

## 8. Legacy 遷移

可從 `../封存/StrawWU-legacy-2026-07-02` 遷移：

- `strawwu-nt/`、`strawwu-runtime/`、`strawwu-kernel-bridge/` → `components/`
- `strawwu-control-center/` → `components/control-center/`
- **不遷移** 舊 `strawwu-os-image/scripts/build-iso.sh`（mmdebstrap 管線）
