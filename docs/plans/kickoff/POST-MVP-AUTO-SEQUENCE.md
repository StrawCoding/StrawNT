# StrawWU Post-MVP 全自動鎖序

| 項目 | 值 |
|------|-----|
| 總 stage 數 | **14** |
| 前置 | Ubuntu 26.04 遷移 7 段（`u26-m7-closeout` PASS） |
| 起點 | `post-d1-strawwu-drivers` |
| 終點 | `post-v09-engineering-closeout` |
| 路線圖 | `docs/plans/strawwu-post-mvp-roadmap.md` |

## 完整管線

```
Wave 47 → w8-mvp-closeout
  → Ubuntu 26.04 遷移 7 段（u26-m1 … u26-m7）
  → Post-MVP 14 段（本文件）
```

## 鎖序

```
post-d1-strawwu-drivers
→ post-hw-t1-live-usb
→ post-hw-t2-installed
→ post-ddp-rootfs
→ post-q3-mfp-smoke
→ post-d7-software-sources
→ post-ux-theme-curation
→ post-v06-closeout
→ post-upg-rollback
→ post-sec-secureboot-route
→ post-ci-kernel-selfhosted
→ post-hw-t3-wincompat
→ post-q8-golden-apps
→ post-v09-engineering-closeout
```

## 規則

1. `w8-mvp-closeout` PASS → 自動 launch `u26-m1-base-clone`（非直接 post-d1）
2. `u26-m7-closeout` PASS → 自動 launch `post-d1-strawwu-drivers`
3. 每 post stage PASS → 自動 launch 下一段
