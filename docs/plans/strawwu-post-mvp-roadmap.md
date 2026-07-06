# StrawWU Post-MVP 長任務路線圖

| 版本 | 2.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 前置 | Ubuntu 26.04 遷移 `u26-m7-closeout` PASS |
| 差距來源 | `strawwu-distro-comparison-v5-2026-07-06.html` |

## 1. 目的

MVP（v0.5.0.0）+ Ubuntu 26.04 遷移完成後，**自動接續** 14 段 Post-MVP 鎖序長任務，補齊與 Mint / Pop!_OS / Zorin 等成熟發行版的差距。

## 2. 完整管線順序

```
Wave 47 段 → w8-mvp-closeout
  ↓
Ubuntu 26.04 遷移 7 段（u26-m1 … u26-m7）
  ↓
Post-MVP 14 段（post-d1 … post-v09）
```

## 3. 管線配置

| 項目 | 值 |
|------|-----|
| Ubuntu 26.04 | `ubuntu_2604_locked_sequence`（7 段） |
| Post-MVP | `post_mvp_locked_sequence`（14 段） |
| 接續 | `longtask_ubuntu_2604_transition_next.sh` / `longtask_post_mvp_transition_next.sh` |
| MVP 終點 | `w8-mvp-closeout` → `u26-m1-base-clone` |
| 遷移終點 | `u26-m7-closeout` → `post-d1-strawwu-drivers` |

## 4. Post-MVP 鎖序（14 段）

```
post-d1-strawwu-drivers
→ post-hw-t1-live-usb
→ post-hw-t2-installed
→ post-ddp-rootfs
→ post-q3-mfp-smoke
→ post-d7-software-sources      # 新增：軟體源 UI（D7）
→ post-ux-theme-curation          # 新增：深色主題（B14）
→ post-v06-closeout
→ post-upg-rollback
→ post-sec-secureboot-route
→ post-ci-kernel-selfhosted
→ post-hw-t3-wincompat
→ post-q8-golden-apps
→ post-v09-engineering-closeout
```

## 5. 階段邊界

### v0.5 MVP（Wave）
- noble 24.04.2 基線；終點 `make test-wave-all-pass`

### Ubuntu 26.04（u26 7 段）
- 基底升級至 Resolute；終點 `make test-ubuntu-2604-all-pass`

### v0.6 驅動與硬體（Post-MVP 段 1–8）
- drivers + HW + DDP + MFP + software-sources + theme
- 終點：`make test-post-mvp-v06-closeout`

### v0.7–v0.9 工程（Post-MVP 段 9–14）
- 終點：`make test-post-mvp-all-pass`

## 6. 相關子計畫

| 文件 | 用途 |
|------|------|
| `strawwu-ubuntu-2604-migration-plan.md` | 26.04 遷移 |
| `strawwu-drivers-plan.md` | Linux GPU/firmware |
| `strawwu-d7-software-sources-plan.md` | 軟體源 UI |
| `strawwu-ux-theme-curation-plan.md` | 深色主題 |
| `ubuntu-base-target.json` | active/target 版本鎖定 |
