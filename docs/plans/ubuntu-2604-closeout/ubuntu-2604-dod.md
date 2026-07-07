# StrawWU Ubuntu 26.04 遷移 Definition of Done

| 欄位 | 值 |
|------|-----|
| 產品目標 | v0.6.0.0-target（Resolute 基底） |
| 建置版本 | 見 VERSION |
| 遷移段數 | 7（u26-m1 → u26-m7-closeout） |
| 基線 | Ubuntu 26.04 LTS Resolute Raccoon + StrawWU cleanroom |

## 1. 遷移目標（migration-plan §1）

| # | 項目 | 狀態 | 證據 |
|---|------|------|------|
| 1 | active 基底切換至 26.04 resolute | ✅ | ubuntu-base-target.json、test-u26-base-clone |
| 2 | kernel rebase 至 resolute 6.14+ / 7.0.0-strawwu | ✅ | linux-image-strawwu deb、test-u26-kernel-rebase |
| 3 | 全部 strawwu-* deb 對 resolute 重編 | ✅ | .debs-rebuild-ok、test-u26-debs-rebuild |
| 4 | APT suite noble→resolute | ✅ | apt-repo-baseline、strawwu.sources、test-u26-suite-migrate |
| 5 | technical-references 刷新 | ✅ | catalog.json resolute、test-u26-techrefs-refresh |
| 6 | release-iso boot + install-firstboot E2E | ✅ | boot-result、firstboot-e2e、test-u26-regression-e2e |
| 7 | closeout 報告 + VERSION bump | ✅ | 本文件、HTML、ubuntu-2604-status.json |

## 2. 各段摘要

| 段 | ID | 重點 |
|----|-----|------|
| M1 | u26-m1-base-clone | ISO 下載、layered rootfs、active 切換 |
| M2 | u26-m2-kernel-rebase | linux 7.0.0-strawwu、strawwu_ipc.ko |
| M3 | u26-m3-debs-rebuild | 22 strawwu-* deb @ VERSION |
| M4 | u26-m4-suite-migrate | dists/resolute、publish-debs |
| M5 | u26-m5-techrefs-refresh | catalog ubuntu_release=resolute |
| M6 | u26-m6-regression-e2e | release-iso BIOS+UEFI、FIRSTBOOT_OK |
| M7 | u26-m7-closeout | 全段 PASS 彙整、HTML hermes-deliver |

## 3. 對比基線更新（migration-plan §6）

遷移完成後發行版對比統一為：

- **主基線**：Ubuntu 26.04 LTS Resolute
- **對照**：Mint 22.x / Pop!_OS / Zorin 18 / elementary OS 8

## 4. 風險緩解驗收

| 風險 | 緩解驗收 |
|------|----------|
| Calamares 3.x API | shellprocess_initramfs-resolute.conf、install-firstboot E2E PASS |
| layered squashfs | clone-ubuntu-base unsquashfs、M1 PASS |
| kernel 6.14 模組 ABI | M2 deb + initrd splice |
| noble→resolute 套件更名 | meta-audit resolute wallpapers、M3 PASS |

## 5. 驗收閘門

```bash
make test-ubuntu-2604-all-pass   # 7/7 stages + active resolute
make preflight                   # 全 Wave + Post-MVP 基礎設施
```

## 6. 產物索引

| 類型 | 路徑 |
|------|------|
| 遷移狀態 | `docs/plans/baselines/ubuntu-2604-status.json` |
| Stage reports | `docs/plans/stage-reports/U26-M*.md`（7 份） |
| HTML 報告 | `docs/plans/ubuntu-2604-closeout/html/ubuntu-2604-closeout-report.html` |
| 遷移計畫 | `docs/plans/strawwu-ubuntu-2604-migration-plan.md` |
| release ISO | `os-image/output/StrawWU-<VERSION>-amd64.iso` |

## 7. 後續

`u26-m7-closeout` PASS → 自動啟動 **post-d1-strawwu-drivers**（Post-MVP 12+2 track）。
