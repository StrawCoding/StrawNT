# StrawWU Phase 路線圖（重啟版）

| 版本 | 2.0-reboot |
|------|------------|
| 日期 | 2026-07-02 |

## Phase 0 — Ubuntu Clone 骨架 ✅ 當前

| # | 驗收標準 | 驗證 |
|---|----------|------|
| 0.1 | 新 repo 骨架、docs、Makefile | 檔案存在 |
| 0.2 | `make preflight` exit 0 | CI |
| 0.3 | 舊版封存 + tag `legacy/archive-2026-07-02` | 封存目錄 |

## Phase 1 — Ubuntu Clone 管線

| # | 驗收標準 |
|---|----------|
| 1.1 | `clone-ubuntu-base.sh` 成功提取 noble desktop rootfs |
| 1.2 | rootfs 內含 `calamares-settings-ubuntu-common` |
| 1.3 | `build-iso.sh` 產出可開機 ISO（沿用 Ubuntu kernel） |
| 1.4 | QEMU `boot-test-iso` serial marker PASS |

## Phase 2 — 自訂 Kernel

| # | 驗收標準 |
|---|----------|
| 2.1 | `kernel/` 產出 `linux-image-strawwu` .deb |
| 2.2 | `swap-kernel.sh` 在 chroot 成功替換且可開機 |
| 2.3 | `uname -r` 顯示 strawwu kernel version |

## Phase 3 — Calamares 安裝 E2E

| # | 驗收標準 |
|---|----------|
| 3.1 | preflight 靜態檢查 ALL PASS |
| 3.2 | QEMU 安裝到 virtio 空白碟成功 |
| 3.3 | 安裝後 BIOS/UEFI 雙韌體開機 |

## Phase 4+ — StrawWU 元件

自 legacy 遷移 NT/runtime/control-center，鎖序推進。詳見封存版 `docs/phase-roadmap.md` Phase 2–9。

## v2.0 Release

- `.iso` + `SHA256SUMS` + `sha256sum -c`
- CI boot/install 證據
- HTML 報告 hermes-deliver 交付
