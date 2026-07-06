# StrawWU Post-MVP 長任務路線圖

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 前置 | Wave 47 段 MVP（`w8-mvp-closeout` PASS） |
| 差距來源 | `strawwu-distro-gap-plan-v3-2026-07-06.html` |

## 1. 目的

MVP（v0.5.0.0）完成後，**自動接續** 12 段 Post-MVP 鎖序長任務，補齊與 Mint / Pop!_OS / Zorin 等成熟發行版的差距，重點在 **Linux 主機驅動 UX**、**實機硬體矩陣**、**device-proxy OS 整合** 與 **發行版級工程**。

## 2. 管線配置

| 項目 | 值 |
|------|-----|
| 配置 | `~/.hermes/config/task-workers/projects/strawwu.json` → `post_mvp_locked_sequence` |
| 接續 | `longtask_post_mvp_transition_next.sh` |
| 路由 | `longtask_transition_dispatch.sh`（wave / post_mvp / phase） |
| MVP 終點接續 | `w8-mvp-closeout` PASS → 自動 launch `post-d1-strawwu-drivers` |
| 全 PASS 驗證 | `make test-post-mvp-all-pass` |

## 3. 鎖序（12 段）

```
post-d1-strawwu-drivers      # B1 — Hub 驅動分頁（對標 Mint Driver Manager）
→ post-hw-t1-live-usb        # B2 — ≥3 台實機 Live USB
→ post-hw-t2-installed       # B3 — 安裝後 smoke + suspend + HiDPI
→ post-ddp-rootfs            # B4 — DDP0–3 rootfs 整合
→ post-q3-mfp-smoke          # B5 — MFP 列印+掃描
→ post-v06-closeout          # v0.6 驅動/硬體驗收
→ post-upg-rollback          # C — upgrade rollback
→ post-sec-secureboot-route  # C — Secure Boot 路線
→ post-ci-kernel-selfhosted  # C — Q6 self-hosted kernel CI
→ post-hw-t3-wincompat       # C — Win compat 實機 smoke
→ post-q8-golden-apps        # C — Q8 golden apps
→ post-v09-engineering-closeout
```

## 4. 階段邊界

### v0.5 MVP（Wave，已完成中）
- 不要求 strawwu-drivers、實機 HW T1/T2、Secure Boot、golden apps
- 終點：`make test-wave-all-pass`

### v0.6 驅動與硬體（Post-MVP 段 1–6）
- strawwu-drivers + 實機 HW T1/T2 + DDP rootfs + MFP smoke
- 終點：`make test-post-mvp-v06-closeout`

### v0.7–v0.9 發行版工程（Post-MVP 段 7–12）
- rollback、SB 路線、kernel CI、HW T3、Q8 golden apps
- 終點：`make test-post-mvp-all-pass`

### v1.0 正式版
- **BLOCKED** — 需 `.official-release-authorized` + 使用者 MAJOR 授權
- 不在 post_mvp 自動鎖序內

## 5. 誠實邊界

- **不可支援**：載入 Windows .sys；僅 .sys 專業儀器（Tier F）
- **PARTIAL 預期**：反作弊、遊戲效能、無實機時 HW 維持 T0
- **資源**：HW T1/T2 需 ≥3 台實機；無硬體時 stage 可標 SKIP 但不可偽 PASS

## 6. 相關子計畫

| 文件 | 用途 |
|------|------|
| `strawwu-drivers-plan.md` | Linux GPU/firmware 策展 |
| `strawwu-hardware-compatibility-test-matrix.md` | T0→T3 矩陣 |
| `components/specs/device-driver-proxy.md` | Win 裝置代理四層 |
| `strawwu-security-trust-model.md` | Secure Boot 路線 |
| `strawwu-deferred-scope.md` | 仍延後項目（備份/多使用者等） |

## 7. Hermes 規則

1. 每 stage PASS → 自動 launch 下一段（**不詢問使用者**）
2. FAIL → Cursor 自修；連續 FAIL >10 → 通知使用者
3. 客人原則：Hermes 只回報結果+log，不給技術方向
