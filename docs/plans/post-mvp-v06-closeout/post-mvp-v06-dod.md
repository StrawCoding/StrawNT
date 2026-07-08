# StrawWU Post-MVP v0.6 Definition of Done

| 欄位 | 值 |
|------|-----|
| 產品目標 | v0.6.0.0-target（驅動與硬體） |
| 建置版本 | 見 VERSION |
| Post-MVP 段數 | 10（post-d1 → post-v06-closeout） |
| 基線 | Ubuntu 26.04 LTS Resolute + StrawWU fork 基底 |

## 1. v0.6 目標（post-mvp-roadmap §5）

| # | 項目 | 狀態 | 證據 |
|---|------|------|------|
| 1 | Linux GPU/firmware 驅動管理（D1） | ✅ | strawwu-drivers deb、Hub 驅動分頁、drivers-hub-baseline |
| 2 | HW T1 Live USB 矩陣（≥3 physical-live） | ✅ | hw-t1-live-usb-baseline、hw-matrix-results.json |
| 3 | HW T2 已安裝系統矩陣 | ✅ | hw-t2-installed-baseline |
| 4 | 筆電周邊（觸控板/Fn、webcam、指紋） | ✅ | hw4-peripherals-baseline |
| 5 | Device Driver Proxy rootfs 整合（DDP） | ✅ | device-proxy-hub-baseline、strawwu-device-proxy |
| 6 | 印表機 MFP 列印+掃描 smoke（Q3） | ✅ | mfp-smoke-baseline |
| 7 | Calamares LUKS + 雙系統安裝（I2） | ✅ | calamares-luks-dualboot-baseline |
| 8 | 軟體源 UI（D7） | ✅ | software-sources-hub-baseline、strawwu-software-sources |
| 9 | 深色主題策展（UX） | ✅ | ux-theme-curation-baseline、strawwu-gtk-theme |
| 10 | v0.6 closeout 報告 + HTML | ✅ | 本文件、post-mvp-status.json、HTML hermes-deliver |

## 2. 各段摘要

| 段 | ID | 重點 |
|----|-----|------|
| D1 | post-d1-strawwu-drivers | ubuntu-drivers 包裝 + Hub 驅動分頁 |
| HW1 | post-hw-t1-live-usb | Live USB physical-live 矩陣 ≥3 |
| HW2 | post-hw-t2-installed | 已安裝系統 HW 矩陣 |
| HW4 | post-hw4-peripherals | 觸控板/Fn、webcam、指紋 |
| DDP | post-ddp-rootfs | device-proxy rootfs + Hub |
| Q3 | post-q3-mfp-smoke | CUPS 列印 + SANE 掃描 smoke |
| I2 | post-i2-calamares-luks | LUKS 加密 + 雙系統 Calamares |
| D7 | post-d7-software-sources | 軟體源管理 UI |
| UX | post-ux-theme-curation | StrawWU-Dark GTK + icon 策展 |
| V06 | post-v06-closeout | 全段 PASS 彙整、HTML、VERSION bump |

## 3. 產品決策對齊（Q1–Q8）

| 決策 | v0.6 範圍 | 驗收 |
|------|-----------|------|
| Q2 Tier4 VFIO+microvm | Phase6.12 PoC（Post-MVP 後段） | 不在 v0.6 blocking |
| Q3 MFP 列印+掃描 | post-q3-mfp-smoke | mfp-smoke-baseline PASS |
| Q4 裝置代理預設開放 | post-ddp-rootfs | device-proxy-hub-baseline |
| Q5 社群 device_profile PR | DDP manifest 可擴展 | device_profile schema |
| Q6 self-hosted CI kernel | v0.7+ post-ci-kernel-selfhosted | deferred |
| Q7 反作弊 | v0.7+ post-w7-anticheat-substantive | deferred |
| Q8 Office/Steam/Epic launcher | v0.7+ post-q8-golden-apps | deferred |

## 4. Phase 6 政策摘要

- 預設 **SubsystemSession（native）** — 禁止 WinBox / strawwu-box
- container / microvm 僅覆寫路徑
- 裝置代理（DDP）預設開放，Hub 可管理

## 5. 延後範圍（v0.7+，非 blocking）

- HW T3 wincompat 實機（post-hw-t3-wincompat）
- HW5 stable gate ≥80%（post-hw5-stable-gate）
- 升級 rollback、Secure Boot、CVE 政策、開機回歸 CI
- self-hosted CI kernel build、反作弊實質驗收
- Office/Steam/Epic/三角洲啟動器（Q8）
- 時光機備份（post-backup-timeshift）

## 6. 驗收閘門

```bash
make test-post-mvp-v06-closeout   # v0.6 DoD + 9 stage gates + HTML
make preflight                    # 全 Wave + Post-MVP 基礎設施
```

Hermes state 9/9 prerequisite stages PASS 後，closeout stage 由 Hermes mark。

## 7. 產物索引

| 類型 | 路徑 |
|------|------|
| Post-MVP 狀態 | `docs/plans/baselines/post-mvp-status.json` |
| Stage reports | `docs/plans/stage-reports/POST-*.md`（10 份） |
| HTML 報告 | `docs/plans/post-mvp-v06-closeout/html/post-mvp-v06-closeout-report.html` |
| 路線圖 | `docs/plans/strawwu-post-mvp-roadmap.md` |
| HW 矩陣 | `docs/plans/hw-matrix-results.json` |
| release ISO | `os-image/output/StrawWU-<VERSION>-amd64.iso` |

## 8. 後續

`post-v06-closeout` PASS → 自動啟動 **post-upg-rollback**（v0.7 工程段，勿問使用者）。
