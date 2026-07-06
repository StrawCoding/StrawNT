# StrawWU Fork 基底遷移計畫

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 前置 | Ubuntu 26.04 遷移 `u26-m7-closeout` PASS |
| 後續 | Post-MVP 21 段（驅動/硬體/工程 track） |

## 1. 目的

將 StrawWU 建置模型從 **cleanroom clone**（每次從官方 ISO 解包）改為 **fork 基底**（版本化 fork manifest + 可重建 snapshot），以保留更多自定義空間，對齊 Linux Mint / Pop!_OS / Zorin 的 fork 發行版模式。

## 2. 為何 fork

| cleanroom clone 限制 | fork 優勢 |
|---------------------|-----------|
| 每次 build 從 vanilla Ubuntu 重來 | 持久化 fork 基底，增量修改 |
| 僅能 overlay deb，難改 base 套件 | 可 remove/replace/pin 任意 Ubuntu 套件 |
| repo ~43MB，無 base 狀態 | manifest + snapshot 可追蹤 base 差異 |
| 自訂空間受限於 chroot 腳本 | 可 fork 個別 upstream 套件（desktop、gnome 等） |
| 難做 Mint 級 Driver Manager 整合 | 自有 fork APT suite 可策展驅動/meta 包 |

## 3. 架構

```
官方 Ubuntu 26.04 ISO（僅 fork-f1 種子或 manifest 重建時使用）
        │
        ▼ fork-baseline-snapshot（u26 驗證過的 rootfs）
   fork-base/manifest.json + snapshots/*.tar.zst（gitignore）
        │
        ▼ fork-sync-base（manifest apply + snapshot restore）
   StrawWU fork rootfs（可 remove/replace/pin 套件）
        │
        ▼ swap-kernel + strawwu debs + fork package overlays
   release-iso
```

### 基底模式

| 模式 | 環境變數 | marker | 用途 |
|------|----------|--------|------|
| clone | `STRAWWU_BASE_MODE=clone` | `.clone-ubuntu-base-ok` | 舊路徑；u26 完成前 |
| fork | `STRAWWU_BASE_MODE=fork` | `.fork-sync-base-ok` | 新路徑；fork-f7 後預設 |

配置：`docs/plans/ubuntu-base-target.json` → `base_mode`

## 4. 鎖序（7 段）

配置：`~/.hermes/config/task-workers/projects/strawwu.json` → `fork_locked_sequence`

```
fork-f1-baseline-snapshot   自 u26 驗證 rootfs 建立 fork baseline snapshot
fork-f2-manifest-repo       packages/remove/pin manifest 進 repo
fork-f3-build-pipeline      Makefile/build-iso 支援 fork 模式
fork-f4-package-overlays    os-image/fork/packages/ 可 fork upstream 套件
fork-f5-apt-fork-suite      strawwu-fork APT suite + publish 整合
fork-f6-regression-e2e      fork base boot + install E2E 全回歸
fork-f7-closeout            base_mode=fork 設為預設 + HTML 報告
```

## 5. 目錄結構

```
os-image/fork-base/
├── manifest.json           # schema、ubuntu 版本、snapshot 校驗
├── packages/
│   ├── include.txt         # 額外安裝
│   ├── remove.txt          # 移除（purge 遙測等）
│   ├── replace.json        # 替換映射 {ubuntu_pkg: strawwu_pkg}
│   └── pins.txt            # apt pin 優先級
├── overrides/              # 設定檔覆寫（etc/ 相對路徑）
└── snapshots/              # gitignore — tar.zst baseline

os-image/fork/packages/     # fork 個別 upstream 套件的 debian/ 原始碼
os-image/scripts/
├── fork-baseline-snapshot.sh
├── fork-sync-base.sh
└── fork-apply-manifest.sh
```

## 6. 與 Post-MVP 的關係

fork 完成後才接 Post-MVP，因為驅動 UI（post-d1）、軟體源（post-d7）等需 fork APT suite 支撐。

```
Wave 47 → u26 7 段 → fork 7 段 → Post-MVP 21 段
```

## 7. 驗收

- `make test-fork-roadmap` PASS
- fork-f6：boot-test + install-firstboot E2E PASS on fork base
- fork-f7：`base_mode=fork` in ubuntu-base-target.json
- HTML 報告 hermes-deliver
