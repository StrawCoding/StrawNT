# POST-V06-closeout — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-v06-closeout` |
| 版本 | `0.6.3.11`（`0.6.3.10` → `0.6.3.11`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T09:59+08:00 |
| Worker 回合 | 階段 1/8（post-v06-closeout worker，本回合續跑驗證） |
| Git 狀態 | 變更未 commit（待 Hermes closeout） |

| Preflight 耗時 | ~243s（3007 行 log） |

## 摘要

完成 Post-MVP **v0.6 驅動與硬體 closeout**：彙整 9 段 prerequisite stage（D1、HW T1/T2、HW4、DDP、MFP、LUKS、D7、UX theme）Hermes PASS 證據；新增 `post-mvp-v06-dod.md`、Teal 深色 HTML hermes-deliver 報告、validate/render 腳本與 preflight 閘門；VERSION bump 至 `0.6.3.11`；`post-mvp-status.json` 更新為 9/21 PASS（v0.6 子集 9/10，closeout 待 Hermes mark）。

## 交付物

| 類型 | 路徑 |
|------|------|
| DoD | `docs/plans/post-mvp-v06-closeout/post-mvp-v06-dod.md` |
| HTML（hermes-deliver） | `docs/plans/post-mvp-v06-closeout/html/post-mvp-v06-closeout-report.html` |
| 驗證腳本 | `tests/post-mvp-v06-closeout/validate-post-mvp-v06-closeout.py` |
| HTML 渲染器 | `tests/post-mvp-v06-closeout/render-html.py` |
| Preflight gate | `tests/preflight/test-post-mvp-v06-closeout.sh` |
| Post-MVP 狀態 | `docs/plans/baselines/post-mvp-status.json` |
| baseline | `docs/plans/baselines/post-mvp-v06-closeout-baseline.json` |

## v0.6 段彙整（9 prerequisite + closeout）

| # | 階段 ID | 重點 | Hermes |
|---|---------|------|--------|
| 1 | post-d1-strawwu-drivers | strawwu-drivers + Hub 驅動分頁 | PASS |
| 2 | post-hw-t1-live-usb | Live USB physical-live ≥3 | PASS |
| 3 | post-hw-t2-installed | 已安裝 HW 矩陣 | PASS |
| 4 | post-hw4-peripherals | 觸控板/Fn、webcam、指紋 | PASS |
| 5 | post-ddp-rootfs | Device Driver Proxy rootfs | PASS |
| 6 | post-q3-mfp-smoke | MFP 列印+掃描 smoke | PASS |
| 7 | post-i2-calamares-luks | LUKS + 雙系統 Calamares | PASS |
| 8 | post-d7-software-sources | 軟體源 UI | PASS |
| 9 | post-ux-theme-curation | StrawWU-Dark 主題策展 | PASS |
| 10 | post-v06-closeout | 本 closeout | IN_PROGRESS |

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.10` → `0.6.3.11` |
| `hub/package.json` | 版本同步 |
| `docs/plans/post-mvp-v06-closeout/` | **新增** DoD + HTML 目錄 |
| `tests/post-mvp-v06-closeout/` | **新增** validate + render |
| `tests/preflight/test-post-mvp-v06-closeout.sh` | 擴充完整 closeout gate |
| `Makefile` | preflight 納入 + test target 串 validate |
| `docs/plans/stage-reports/POST-V06-closeout-report.md` | 本報告 |

## 測試證據

### `make test-post-mvp-v06-closeout`（2026-07-08T09:55）

```
$ make test-post-mvp-v06-closeout
=== POST-V06 closeout preflight ===
PASS: v0.6 prerequisite Hermes stages 9/9 PASS
PASS: HTML post-mvp-v06-closeout-report.html rendered (Teal + hermes-deliver)
=== Post-MVP v0.6 closeout validation ===
PASS: 9 stage reports + 9 baselines + hw-matrix-results.json
PASS: make test-drivers … test-ux-theme-curation (9 stage gates)
PASS: post-mvp-status.json 9/21 PASS (v0.6 subset 9/10)
=== Post-MVP v0.6 closeout validation: PASS ===
=== POST-V06 closeout done: PASS ===
exit code: 0
```

完整 log：`/tmp/test-post-mvp-v06-closeout.log`（139 行）

### `make preflight`（2026-07-08T09:59）

```
$ make preflight
…（全套 preflight 閘門，含 test-post-mvp-v06-closeout）
POST-MVP INFRASTRUCTURE OK
=== FORK-F7 closeout done: PASS ===
=== POST-V06 closeout done: PASS ===
exit code: 0
```

完整 log：`/tmp/preflight-post-v06.log`（3007 行，耗時 ~243s）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-post-mvp-v06-closeout
make preflight
```

## 下一階段

Hermes mark PASS → 自動啟動 `post-upg-rollback`（依 POST-MVP-AUTO-SEQUENCE）

## Commit message（建議）

```
feat(post-v06): v0.6 drivers/HW closeout DoD gate + HTML report

- post-mvp-v06-dod.md + hermes-deliver HTML + validate/preflight scripts
- Makefile test-post-mvp-v06-closeout; preflight chain extended
- VERSION 0.6.3.11
Tests: make test-post-mvp-v06-closeout; make preflight
Issue: post-v06-closeout v0.6.3.11
```

HTML 重新產生：`python3 tests/post-mvp-v06-closeout/render-html.py`
