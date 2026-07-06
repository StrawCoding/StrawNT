# StrawWU Ubuntu 26.04 LTS（Resolute）遷移計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 前置 | Wave MVP `w8-mvp-closeout` PASS（noble 24.04.2 基線） |
| 後續 | Post-MVP 12+2 段（驅動/硬體/工程 track） |

## 1. 目的

將 StrawWU 上游基底從 **Ubuntu 24.04.2 noble** 升級至 **Ubuntu 26.04 LTS Resolute Raccoon**，使對比基線、kernel、Calamares、APT suite 與成熟發行版（Mint 22 / Pop 24.04+ / Zorin 18）對齊。

## 2. 為何 MVP 後才遷移

| 原因 | 說明 |
|------|------|
| 鎖序完整性 | 現行 Wave 41/47 在 noble 上已驗證；中途換基底會 invalidate 進行中證據 |
| 可回滾 | noble rootfs 快照保留至 u26-m1 PASS |
| 治本 | 一次遷移 + 全量 regression，而非邊做 Wave 邊換版本 |

## 3. 鎖序（7 段）

配置：`~/.hermes/config/task-workers/projects/strawwu.json` → `ubuntu_2604_locked_sequence`

```
u26-m1-base-clone       # 下載 26.04 ISO、提取 rootfs、更新 ubuntu-base-target.json active
→ u26-m2-kernel-rebase  # kernel 樹 rebase 至 resolute 6.14+；LOCALVERSION=-strawwu
→ u26-m3-debs-rebuild   # 全部 strawwu-* deb 對 resolute 重編
→ u26-m4-suite-migrate  # APT suite noble→resolute；publish-debs；sources.list 模板
→ u26-m5-techrefs-refresh # refresh-technical-references.sh 拉 resolute 上游文件
→ u26-m6-regression-e2e # release-iso boot-test + install-firstboot E2E 全回歸
→ u26-m7-closeout       # HTML 報告 + VERSION bump + hermes-deliver
```

## 4. 各段交付

### u26-m1-base-clone
- `STRAWWU_UBUNTU_VERSION=26.04.0` / `STRAWWU_APT_SUITE=resolute`
- `os-image/work/.clone-ubuntu-base-ok` 指向 resolute rootfs
- `docs/plans/baselines/ubuntu-base-target.json` → `active` 切換為 target
- `make test-u26-base-clone` PASS

### u26-m2-kernel-rebase
- `kernel/` 對 resolute linux-source 重編
- `linux-image-*-strawwu` .deb 產出
- `make test-u26-kernel-rebase` PASS

### u26-m3-debs-rebuild
- `os-image/debs/*` 全部 `make build-debs` 對 resolute chroot
- meta-audit allowlist 更新（`ubuntu-wallpapers-resolute` 等）
- `make test-u26-debs-rebuild` PASS

### u26-m4-suite-migrate
- `scripts/publish-debs.sh` → `dists/resolute/`
- `tests/preflight/test-apt-repo.sh` 驗 resolute Release.gpg
- security-baseline / apt-repo-baseline JSON 更新
- `make test-u26-suite-migrate` PASS

### u26-m5-techrefs-refresh
- `docs/technical-references/` catalog 更新 `ubuntu_release: resolute`
- `scripts/refresh-technical-references.sh` 執行完成
- `make test-u26-techrefs-refresh` PASS

### u26-m6-regression-e2e
- `make release-iso` → `preflight-iso-before-boot` → `boot-test-release-iso`
- `make test-install-firstboot-e2e` FIRSTBOOT_OK
- `make test-u26-regression-e2e` PASS

### u26-m7-closeout
- `make test-ubuntu-2604-all-pass`
- stage report + HTML hermes-deliver
- VERSION bump（preview d）

## 5. 風險與緩解

| 風險 | 緩解 |
|------|------|
| Calamares 3.x API 變更 | 對照 `calamares-settings-ubuntu` resolute 包；保留 offscreen E2E |
| layered squashfs 結構差異 | clone 腳本已支援 noble 分層；u26-m1 驗證 resolute 層名 |
| kernel 6.14 模組 ABI | u26-m2 全量 rebuild + initrd splice 重驗 |
| noble→resolute 套件更名 | meta-audit + u26-m3 掃描 `ubuntu-*` 殘留 |

## 6. 對比書基線更新

遷移完成後，發行版對比基線統一為：
- **主基線**：Ubuntu 26.04 LTS Resolute
- **對照**：Mint 22.x / Pop!_OS / Zorin 18 / elementary OS 8
- 文件：`strawwu-distro-comparison.md` v5

## 7. Hermes 規則

1. `w8-mvp-closeout` PASS → 自動 launch `u26-m1-base-clone`（非 post-d1）
2. `u26-m7-closeout` PASS → 自動 launch `post-d1-strawwu-drivers`
3. FAIL → Cursor 自修；連續 FAIL >10 → 通知使用者
