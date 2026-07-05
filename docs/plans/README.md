# StrawWU 計畫文件索引

| 總體計畫 | 版本 | 日期 |
|----------|------|------|
| **Master Plan v4** | 合併 21 份子計畫 + 6 項 v4 補充 | 2026-07-04 |

## 核心工作流（v2 原始 9 份）

| 文件 | 代號 | 說明 |
|------|------|------|
| `strawwu-initrd-plan.md` | S0–S5 | initrd / casper 自製 |
| `strawwu-installer-plan.md` | I0–I5 | Calamares 自製 |
| `strawwu-install-init-plan.md` | N0–N5 | 安裝初始化四件套 |
| `strawwu-ubuntu-components-plan.md` | B0–B5 | Ubuntu 部件替換 |
| `strawwu-flathub-plan.md` | F0–F5 | Flathub 預設 |
| `strawwu-desktop-plan.md` | D0–D5 | 自研桌面 |
| `strawwu-app-registry-plan.md` | R0–R5 | App 登錄表 |
| `strawwu-distro-gap-analysis.md` | — | 差距分析（48 維度） |
| `strawwu-distro-comparison.md` | — | 發行版策略對照 |

## 橫切 / 治理（v3 新增 10 份）

| 文件 | 代號 |
|------|------|
| `strawwu-release-engineering-plan.md` | RE0–RE6 |
| `strawwu-security-trust-model.md` | SEC0–SEC5 |
| `strawwu-legal-compliance-plan.md` | LEG0–LEG4 |
| `strawwu-hardware-compatibility-test-matrix.md` | HW0–HW5 |
| `strawwu-upgrade-recovery-plan.md` | UPG0–UPG5 |
| `strawwu-windows-compat-integration-plan.md` | W0–W6 |
| `strawwu-prd-v0.5.md` | PRD |
| `strawwu-ux-design-system.md` | UX0–UX3 |
| `strawwu-observability-debug-plan.md` | OBS0–OBS4 |
| `strawwu-ai-worker-sop.md` | GOV |

## v4 補充（本次新增）

| 文件 | 代號 |
|------|------|
| `strawwu-ci-build-plan.md` | CI0–CI4 |
| `strawwu-localization-ime-plan.md` | L10N0–L10N3 |
| `strawwu-user-docs-plan.md` | DOC0–DOC3 |
| `strawwu-device-proxy-os-plan.md` | DDP0–DDP3 |
| `strawwu-performance-budget-plan.md` | PERF0–PERF2 |
| `strawwu-greeter-session-plan.md` | GRT0–GRT2 |
| `strawwu-deferred-scope.md` | 延後 5 項 · P2/P3 邊界 |

## Kickoff 任務書

**全自動鎖序（47 段）** 見 `kickoff/WAVE-AUTO-SEQUENCE.md`。

| 項目 | 值 |
|------|-----|
| 總 stage | 47 |
| 起點 | `w0-baseline` ✅ PASS |
| 現行 | `w1-b1-purge` 🔄 IN_PROGRESS |
| 終點 | `w8-mvp-closeout` |
| 全 PASS 驗證 | `make test-wave-all-pass` |
| 進度 JSON | `baselines/wave-status.json` |

每 stage 任務書：`docs/plans/kickoff/W*-*.md`（47 份 + 索引）

## 基線 JSON

| 文件 | 說明 |
|------|------|
| `baselines/release-baseline.json` | RE0 發行基線 |
| `baselines/obs-baseline.json` | OBS0 可觀測性基線 |
| `baselines/perf-baseline.json` | PERF0 效能基線 |
| `baselines/wave-status.json` | Wave 0–8 全 stage 狀態（自動更新） |

## Hermes 交付

完整 HTML 報告：`strawwu-master-plan-v4-2026-07-04.html`（hermes-deliver）
