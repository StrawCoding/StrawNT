# StrawWU Post-MVP v0.9 Engineering Definition of Done

| 欄位 | 值 |
|------|-----|
| 產品目標 | 0.9.0.0-target（v0.7–v0.9 工程 track） |
| 建置版本 | 見 VERSION |
| Post-MVP 段數 | 21（post-d1 → post-v09-engineering-closeout） |
| 工程子集 | 11（post-upg-rollback → post-v09-engineering-closeout） |
| 基線 | Ubuntu 26.04 LTS Resolute + StrawWU fork 基底 |

## 1. v0.9 工程目標（post-mvp-roadmap §5）

| # | 項目 | 狀態 | 證據 |
|---|------|------|------|
| 1 | 升級與 rollback（UPG） | ✅ | strawwu-upgrade deb、upgrade-rollback-baseline |
| 2 | Secure Boot 路線（SEC） | ✅ | secureboot-route-baseline、SB shim 文件 |
| 3 | CVE/USN 修補政策（H6） | ✅ | cve-policy-baseline、strawwu-cve-policy |
| 4 | 開機時間 CI 回歸（H5） | ✅ | boot-time-baseline、perf-boot-regression gate |
| 5 | self-hosted CI kernel build（Q6） | ✅ | ci-baseline、kernel CI workflow |
| 6 | 反作弊實質等級（G8） | ✅ | anticheat-substantive-baseline（誠實 PARTIAL） |
| 7 | HW T3 wincompat 實機 smoke | ✅ | hw-t3-wincompat-baseline |
| 8 | 黃金應用啟動器（Q8） | ✅ | golden-apps-launch-baseline（launcher only） |
| 9 | HW5 穩定度 ≥80%（F9） | ✅ | hw5-stable-gate-baseline |
| 10 | 時光機/系統備份（H13） | ✅ | backup-timeshift-baseline、strawwu-backup |
| 11 | v0.9 engineering closeout 報告 + HTML | ✅ | 本文件、post-mvp-status.json、HTML hermes-deliver |

## 2. 工程段摘要（post-upg → post-v09）

| 段 | ID | 重點 |
|----|-----|------|
| UPG | post-upg-rollback | strawwu-upgrade + snapshot rollback + Rescue ISO |
| SEC1 | post-sec-secureboot-route | Secure Boot shim/MOK 路線文件與 preflight |
| SEC2 | post-sec-cve-policy | CVE/USN 修補政策與 Hub 通知 |
| PERF | post-perf-boot-regression | 開機時間 CI 回歸閘門 |
| CI | post-ci-kernel-selfhosted | self-hosted kernel build workflow（Q6） |
| W7 | post-w7-anticheat-substantive | 反作弊實質等級（可正常運行，誠實 PARTIAL） |
| HW3 | post-hw-t3-wincompat | Win compat 硬體實機 smoke |
| Q8 | post-q8-golden-apps | Office/Steam/Epic/三角洲 launcher 驗證 |
| HW5 | post-hw5-stable-gate | T1+T2 穩定率 ≥80% |
| BACKUP | post-backup-timeshift | strawwu-backup 時光機 PoC + Hub 分頁 |
| V09 | post-v09-engineering-closeout | 全 21 段 PASS 彙整、HTML、VERSION bump |

## 3. 產品決策對齊（Q1–Q8）

| 決策 | v0.9 工程範圍 | 驗收 |
|------|---------------|------|
| Q2 Tier4 VFIO+microvm | Phase6.12 PoC（Post-MVP 後 / 1.0 前） | 不在 v0.9 blocking |
| Q3 MFP 列印+掃描 | v0.6 post-q3-mfp-smoke | 已 PASS |
| Q4 裝置代理預設開放 | v0.6 post-ddp-rootfs | 已 PASS |
| Q5 社群 device_profile PR | DDP manifest 可擴展 | device_profile schema |
| Q6 self-hosted CI kernel | post-ci-kernel-selfhosted | ci-baseline PASS |
| Q7 反作弊=可正常運行 | post-w7-anticheat-substantive | PARTIAL 誠實等級 |
| Q8 Office/Steam/Epic launcher | post-q8-golden-apps | launcher only，禁止宣稱登入/遊玩 |
| Q1 預發布範圍 | 待使用者另行提出 | deferred |

## 4. Phase 6 政策摘要

- 預設 **SubsystemSession（native）** — 禁止 WinBox / strawwu-box
- container / microvm 僅覆寫路徑
- Q2 Tier4 VFIO+microvm 納入 Phase6.12 PoC（Post-MVP 後段）

## 5. 全 Post-MVP 管線（21 段）

v0.6 驅動與硬體（10 段）+ v0.7–v0.9 工程（11 段）= **21 段全 PASS** 為 Post-MVP 終點。

| 區間 | 段數 | closeout |
|------|------|----------|
| v0.6 drivers/HW | 10 | post-v06-closeout |
| v0.7–v0.9 engineering | 11 | post-v09-engineering-closeout |

## 6. 驗收閘門

```bash
make test-post-mvp-v09-closeout   # v0.9 DoD + 10 prerequisite gates + HTML
make test-post-mvp-all-pass       # Hermes 21/21 stage PASS
make preflight                    # 全 Wave + Post-MVP 基礎設施
```

Hermes state 20/20 prerequisite stages PASS 後，closeout stage 由 Hermes mark。

## 7. 產物索引

| 類型 | 路徑 |
|------|------|
| Post-MVP 狀態 | `docs/plans/baselines/post-mvp-status.json` |
| Stage reports | `docs/plans/stage-reports/POST-*.md`（21 份） |
| HTML 報告 | `docs/plans/post-mvp-v09-closeout/html/post-mvp-v09-closeout-report.html` |
| 路線圖 | `docs/plans/strawwu-post-mvp-roadmap.md` |
| HW 矩陣 | `docs/plans/hw-matrix-results.json` |
| release ISO | `os-image/output/StrawWU-<VERSION>-amd64.iso` |

## 8. 後續

`post-v09-engineering-closeout` PASS → Post-MVP 管線完成；下一階段為 **official-release**（需 `.official-release-authorized` 與 Q9 1.0.0 授權）。
