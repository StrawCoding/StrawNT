# StrawWU 管理員手冊

本手冊面向**系統管理員與發行維護者**，說明 StrawWU 目標系統的維運、套件、發佈與疑難排解。終端使用者日常操作見 [user-handbook.md](user-handbook.md)。

## 1. 架構概覽

```
ISO (Live) ──Calamares──► 已安裝系統
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
  strawwu-initd        strawwu-target-setup   strawwu-app-registry
  (state.json)         (chroot meta staging)   (使用者應用登記)
         │                    │
         ▼                    ▼
  lifecycle 旗標        meta .deb + initramfs-hooks
```

| 子系統 | 套件／工具 | 用途 |
|--------|------------|------|
| 狀態管理 | `strawwu-initd` | `/var/lib/strawwu/setup/state.json`、lifecycle |
| 安裝 hook | `strawwu-target-setup` | Calamares chroot 內安裝 staged debs |
| 應用登記 | `strawwu-app-registry` | User App Registry（與 compat-db 分離） |
| 開機鏈 | `strawwu-initramfs-hooks` | 剝除 casper hook、強制磁碟 `BOOT=local` |
| 品牌 | `strawwu-target-identity` | GRUB、Plymouth、initramfs 重生 |

## 2. strawwu-initd

CLI 管理安裝後系統狀態：

```bash
strawwu-initd show                    # 顯示 state.json
strawwu-initd repair                  # 修復損毀狀態（備份後重建）
strawwu-initd set <key> <value>       # 設定 lifecycle 旗標
```

常見 lifecycle 鍵：`firstboot_required`、`initramfs_hooks`、`target_identity`。

**repair** 適用於 JSON 損毀、firstboot 迴圈、升級後狀態不一致。詳見 [rescue-guide.md](../rescue-guide.md) §4.1。

## 3. strawwu-target-setup

Calamares `target_setup` 階段執行，亦可在 Live chroot 手動修復：

```bash
strawwu-target-setup --repair-only    # 重新套用 target manifest staged debs
```

`target-manifest.yaml` 定義安裝順序（desktop meta、bug-reporter、firstboot、initramfs-hooks、target-identity 等）。中斷安裝或手動刪除 StrawWU 套件後使用 `--repair-only`。

## 4. Meta 套件與 allowlist

| Meta | 說明 |
|------|------|
| `strawwu-desktop` | 桌面 session、shell、hub、greeter |
| `strawwu-minimal` | 核心 StrawWU 元件 |
| `strawwu-bug-reporter` | 問題回報 |
| `strawwu-firstboot` | 首次設定精靈 |

**meta-audit**（W6-B5）維護 Ubuntu 上游套件 allowlist；禁止未審核的 `ubuntu-*` 品牌套件殘留。執行 `make test-meta-audit` 驗證。

## 5. APT 倉庫與簽章

StrawWU 官方倉庫（W7-RE）：

| 元件 | 路徑／說明 |
|------|------------|
| `strawwu-keyring` | GPG 金鑰，安裝於 `/usr/share/keyrings/` |
| `sources.list.d/strawwu.list` | APT 來源 |
| `make publish-debs` | 從 `os-image/debs/` 建置簽章倉庫 |

客戶端更新：`sudo apt update && sudo apt upgrade`。倉庫 URL 隨發佈管線配置（見 `release-manifest.json`）。

## 6. 發佈與 ISO

### 6.1 ISO 三模式

| 模式 | 用途 | 壓縮 |
|------|------|------|
| dev-vm | 日常開發，rsync 至 VM | 無 ISO |
| dev-iso | 快速 Live 驗證 | zstd |
| release-iso | 正式驗收、發佈 | xz |

Phase 驗收僅用 **release-iso**。詳見 `docs/iso-modes.md`。

### 6.2 發佈產物

```bash
make release-iso
make generate-release-manifest
make release-sign          # SHA256SUMS + GPG
```

產物：`os-image/output/StrawWU-<版本>-amd64.iso`、`release-manifest.json`、簽章檔。

### 6.3 Preflight 閘門

任何改碼後須 `make preflight` PASS，才允許 boot-test／E2E。禁止 `SKIP_SQUASHFS=1` 進 release 驗收。

## 7. initramfs 與開機

**strawwu-initramfs-hooks**（W8-S4）在已安裝系統：

- 剝除 `casper`／`live-boot` initramfs hook（Live 專用）
- 安裝 `conf.d/strawwu-disk-boot`（`BOOT=local`）
- 與 ISO initrd splice（strawwu-live-init／bottom）互補

`strawwu-target-identity` post-install 執行 `update-initramfs` 重生磁碟 initrd。

GRUB 修復見 [rescue-guide.md](../rescue-guide.md) §4.4。

## 8. 硬體相容與 CI

| 資源 | 說明 |
|------|------|
| `docs/plans/hw-matrix-results.json` | GPU／Wi-Fi／suspend／HiDPI 實機結果 |
| `tests/hw/smoke-live.sh` | Live session smoke |
| `make test-hw-matrix` | 矩陣 gate |

維護者合併實機 smoke 輸出至 hw-matrix；使用者見 install-guide §2.4。

## 9. Windows 相容（管理視角）

compat-db 與 User App Registry **分表**：

- **compat-db**：CI 黃金應用、反作弊矩陣、等級 A/B/C/F
- **App Registry**：使用者已安裝應用

Hub 與 `strawwu status` 讀取 compat 摘要。管理員不需手動編輯 compat-db；見 `components/specs/anticheat-compat.md`。

## 10. 觀測與合規

| 項目 | 工具 |
|------|------|
| Bug bundle schema | `strawwu-bug-report` CLI |
| 商標掃描 | `make test-legal-trademark` |
| 遙測清除 | purge-ubuntu-telemetry（無 apport／whoopsie／ubuntu-pro） |
| CI nightly | `make test-ci-nightly` |

## 11. 疑難排解速查

| 問題 | 指令／文件 |
|------|------------|
| meta 不完整 | `strawwu-target-setup --repair-only` |
| state 損毀 | `strawwu-initd repair` |
| initrd 仍含 casper | 確認 `strawwu-initramfs-hooks` 已安裝 |
| registry 不同步 | `strawwu-app-registry scan` |
| 升級失敗 | [upgrade-rescue-guide.md](upgrade-rescue-guide.md) |

## 12. 相關文件

- [user-handbook.md](user-handbook.md) — 終端使用者指南
- [rescue-guide.md](../rescue-guide.md) — Live chroot 救援
- [upgrade-rescue-guide.md](upgrade-rescue-guide.md) — UPG／rollback
- `docs/plans/strawwu-upgrade-recovery-plan.md` — UPG 路線圖
- `docs/iso-modes.md` — ISO 建置模式
