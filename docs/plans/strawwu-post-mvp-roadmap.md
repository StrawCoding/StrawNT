# StrawWU Post-MVP 長任務路線圖

| 版本 | 2.1 |
|------|-----|
| 日期 | 2026-07-06 |
| 前置 | Ubuntu 26.04 遷移 `u26-m7-closeout` PASS |
| 差距來源 | `strawwu-distro-comparison-v5.1-2026-07-06.html`（103 維度，44 項仍落差） |

## 1. 目的

MVP（v0.5.0.0）+ Ubuntu 26.04 遷移完成後，**自動接續** 21 段 Post-MVP 鎖序長任務，補齊與 Mint / Pop!_OS / Zorin 等成熟發行版的差距。

## 2. 完整管線順序

```
Wave 47 段 → w8-mvp-closeout
  ↓
Ubuntu 26.04 遷移 7 段（u26-m1 … u26-m7）
  ↓
Post-MVP 21 段（post-d1 … post-v09）
```

## 3. 管線配置

| 項目 | 值 |
|------|-----|
| Ubuntu 26.04 | `ubuntu_2604_locked_sequence`（7 段） |
| Post-MVP | `post_mvp_locked_sequence`（**21** 段） |
| 接續 | `longtask_ubuntu_2604_transition_next.sh` / `longtask_post_mvp_transition_next.sh` |
| MVP 終點 | `w8-mvp-closeout` → `u26-m1-base-clone` |
| 遷移終點 | `u26-m7-closeout` → `post-d1-strawwu-drivers` |

## 4. Post-MVP 鎖序（21 段）

見 `docs/plans/kickoff/POST-MVP-AUTO-SEQUENCE.md`

### v2.1 新增（對照書未接入項）

| Stage | 對照維度 | 說明 |
|-------|----------|------|
| `post-hw4-peripherals` | E10, E15 | 觸控板/Fn、webcam、指紋 |
| `post-i2-calamares-luks` | C7, C8 | LUKS 加密、雙系統安裝 |
| `post-sec-cve-policy` | H6 | CVE/USN 修補政策 |
| `post-perf-boot-regression` | H5 | 開機時間 CI 回歸 |
| `post-w7-anticheat-substantive` | G8 | 反作弊實質等級（誠實 PARTIAL） |
| `post-hw5-stable-gate` | F9 | 硬體穩定度 ≥80% |
| `post-backup-timeshift` | H13 | 時光機/系統備份 |

## 5. 階段邊界

### v0.5 MVP（Wave）
- noble 24.04.2 基線；終點 `make test-wave-all-pass`

### Ubuntu 26.04（u26 7 段）
- 基底升級至 Resolute；終點 `make test-ubuntu-2604-all-pass`

### v0.6 驅動與硬體（Post-MVP 段 1–10）
- drivers + HW + peripherals + DDP + MFP + LUKS + software-sources + theme
- 終點：`make test-post-mvp-v06-closeout`

### v0.7–v0.9 工程（Post-MVP 段 11–21）
- upgrade、SB、CVE、PERF、CI、anticheat、golden apps、HW5、backup
- 終點：`make test-post-mvp-all-pass`

## 6. 相關子計畫

| 文件 | 用途 |
|------|------|
| `strawwu-ubuntu-2604-migration-plan.md` | 26.04 遷移 |
| `strawwu-drivers-plan.md` | Linux GPU/firmware |
| `strawwu-hw4-peripherals-plan.md` | 筆電周邊 |
| `strawwu-installer-advanced-plan.md` | LUKS/雙系統 |
| `strawwu-d7-software-sources-plan.md` | 軟體源 UI |
| `strawwu-ux-theme-curation-plan.md` | 深色主題 |
| `strawwu-backup-plan.md` | 時光機 |
| `ubuntu-base-target.json` | active/target 版本鎖定 |
