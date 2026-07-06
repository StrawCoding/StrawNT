# StrawWU MVP Definition of Done

| 欄位 | 值 |
|------|-----|
| 產品目標 | v0.5.0.0 (MVP) |
| 建置版本 | 見 VERSION |
| Wave 段數 | 47（w0-baseline → w8-mvp-closeout） |
| 基線 | Ubuntu noble 24.04.2 + StrawWU cleanroom |

## 1. PRD MVP 必備（§5）

| # | 項目 | 狀態 | 證據 |
|---|------|------|------|
| 1 | 全程 StrawWU 品牌（開機→桌面→安裝→firstboot） | ✅ | W3-I3 target-identity、W5-I3、legal-baseline |
| 2 | Flathub 預設、無 Snap | ✅ | W1-F1 flatpak、W1-F2 nosnap、target-flathub-baseline |
| 3 | strawwu-bug-reporter + Hub | ✅ | W2-B2、W4-D3 hub-settings、desktop-baseline |
| 4 | strawwu-calamares-settings + firstboot | ✅ | W2-I1、W5-N3 firstboot、install-firstboot-e2e-baseline |
| 5 | strawwu-shell/session 最小可用 | ✅ | W4-D2 shell、W5-grt-session、shell-baseline |
| 6 | App Registry list/remove | ✅ | W2-R1、W4-R2 apps-page、W6-R5 deep-uninstall |
| 7 | Windows compat ≥1 GUI app E2E smoke | ✅ | W6-W6 wincompat-e2e-baseline |
| 8 | release-iso + SHA256 + boot/install E2E | ✅ | W6-N5/I4、W7-RE manifest-gpg、release-manifest-baseline |

## 2. 成功指標（PRD §8）

| 指標 | v0.5 目標 | 驗收 |
|------|-----------|------|
| 安裝成功率（QEMU E2E） | 100% | install-firstboot-e2e-baseline |
| firstboot 完成率 | ≥95% 新裝 | firstboot-baseline |
| bug bundle 生成成功率 | 100% CLI | bug-reporter preflight |
| 日常 Flathub app 可用 | ≥3 app smoke | target-flathub-baseline |
| Windows GUI smoke | ≥1 app PASS | wincompat-e2e-baseline |

## 3. Wave 0–8 階段摘要

| Wave | 段數 | 重點 | 終端 stage |
|------|------|------|------------|
| W0 | 1 | 基線度量 | w0-baseline |
| W1 | 4 | purge / Flathub / nosnap / initrd | w1-s1-initrd |
| W2 | 5 | bug-reporter / calamares / registry / initd / trust | w2-trust-baseline |
| W3 | 5 | desktop meta / live UX / update / target / wincompat OS | w3-w0-wincompat-baseline |
| W4 | 6 | shell / hub / apps / flathub hub / launcher / l10n | w4-l10n-ime |
| W5 | 8 | firstboot / finished / context / hooks / identity / greeter | w5-grt-session |
| W6 | 8 | install E2E / boot / flathub / audit / uninstall / wincompat / USB / docs | w6-doc1-user-docs |
| W7 | 4 | manifest GPG / apt repo / CI nightly / perf+legal | w7-perf-legal-gate |
| W8 | 6 | hw-matrix / initrd core+bottom / hooks / handbook / **closeout** | w8-mvp-closeout |

## 4. 延後範圍（非 blocking）

依 `strawwu-deferred-scope.md`，以下**不阻擋** MVP closeout：

- 多使用者 / 家庭帳號（v1.0）
- strawwu-backup 時光機（UPG）
- 官方社群 / 支援渠道（TBD 佔位）
- shell 插件 API（v1.0）
- Secure Boot 簽章鏈（v1.0）
- Office/Steam/Epic 完整啟動（Q8 Post-MVP）

## 5. Phase 6 政策摘要

- 預設 **SubsystemSession（native）** — 禁止 WinBox / strawwu-box
- container / microvm 僅覆寫路徑
- Tier4 VFIO+microvm → Phase6.12 PoC（Post-MVP）

## 6. 驗收閘門

```bash
make test-mvp-closeout      # MVP DoD + HTML + stage reports
make test-wave-all-pass     # Hermes state 47/47 PASS（closeout 由 Hermes mark）
make preflight              # 全 Wave preflight 鏈
```

## 7. 產物索引

| 類型 | 路徑 |
|------|------|
| Wave 狀態 | `docs/plans/baselines/wave-status.json` |
| Stage reports | `docs/plans/stage-reports/*.md`（47 份） |
| HTML 報告 | `docs/plans/mvp-closeout/html/mvp-closeout-report.html` |
| 使用者手冊 | `docs/user/handbook/` |
| Release manifest | `scripts/generate-release-manifest.sh` |
| Post-MVP 銜接 | `docs/plans/kickoff/POST-MVP-AUTO-SEQUENCE.md` |

## 8. Closeout 後自動銜接

Hermes mark `w8-mvp-closeout` PASS → 自動啟動 **u26-m1-base-clone**（Ubuntu 26.04 遷移 track）。
