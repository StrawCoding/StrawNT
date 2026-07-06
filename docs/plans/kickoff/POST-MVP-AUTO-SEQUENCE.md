# StrawWU Post-MVP 全自動鎖序

| 項目 | 值 |
|------|-----|
| 總 stage 數 | **21** |
| 前置 | Ubuntu 26.04 遷移 7 段 + Fork 7 段（`fork-f7-closeout` PASS） |
| 起點 | `post-d1-strawwu-drivers` |
| 終點 | `post-v09-engineering-closeout` |
| 路線圖 | `docs/plans/strawwu-post-mvp-roadmap.md` |
| 差距來源 | `strawwu-distro-comparison-v5.1-2026-07-06.html`（103 維度） |

## 完整管線

```
Wave 47 → w8-mvp-closeout
  → Ubuntu 26.04 遷移 7 段（u26-m1 … u26-m7）
  → Fork 7 段（fork-f1 … fork-f7）
  → Post-MVP 21 段（本文件）
```

## 鎖序

```
post-d1-strawwu-drivers
→ post-hw-t1-live-usb
→ post-hw-t2-installed
→ post-hw4-peripherals          # E10/E15 筆電周邊
→ post-ddp-rootfs
→ post-q3-mfp-smoke
→ post-i2-calamares-luks        # C7/C8 LUKS+雙系統
→ post-d7-software-sources
→ post-ux-theme-curation
→ post-v06-closeout
→ post-upg-rollback
→ post-sec-secureboot-route
→ post-sec-cve-policy           # H6 CVE/USN
→ post-perf-boot-regression     # H5 開機回歸
→ post-ci-kernel-selfhosted
→ post-w7-anticheat-substantive # G8 反作弊實質
→ post-hw-t3-wincompat
→ post-q8-golden-apps
→ post-hw5-stable-gate          # F9 HW≥80%
→ post-backup-timeshift         # H13 時光機
→ post-v09-engineering-closeout
```

## 規則

1. `w8-mvp-closeout` PASS → 自動 launch `u26-m1-base-clone`
2. `u26-m7-closeout` PASS → 自動 launch `fork-f1-baseline-snapshot`
3. `fork-f7-closeout` PASS → 自動 launch `post-d1-strawwu-drivers`
4. 每 post stage PASS → 自動 launch 下一段
