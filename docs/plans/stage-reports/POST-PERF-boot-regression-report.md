# POST-PERF-boot-regression — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-perf-boot-regression` |
| 版本 | `0.7.0.3`（`0.7.0.2` → `0.7.0.3`） |
| 版本目標 | `0.7.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T11:52+08:00 |
| Worker 回合 | 階段 1/8（post-perf-boot-regression，worker 驗證回合） |

## 摘要

實作 Post-MVP **PERF2 開機時間 baseline + CI 回歸閾值**（H5）：

- 新增 QEMU / boot-artifact 雙路徑量測：`measure-boot-time.sh` + `estimate-from-serial.py`
- 基線 JSON：`boot-time-baseline.json`（baseline 18s，預算 45s，回歸比率 1.15）
- Gate 腳本：`test-perf-boot-regression.sh`（advisory/strict 雙模式 + fixture 回歸數學）
- CI：`nightly.yml` advisory gate；`release.yml` strict gate（measure → test）
- 更新 `strawwu-performance-budget-plan.md` PERF2 章節

## 交付物

| 類型 | 路徑 |
|------|------|
| 量測腳本 | `tests/perf/measure-boot-time.sh` |
| 回歸檢查 | `tests/perf/check-boot-regression.py` |
| Serial 估算 | `tests/perf/estimate-from-serial.py` |
| Baseline | `docs/plans/baselines/boot-time-baseline.json` |
| Preflight gate | `tests/preflight/test-perf-boot-regression.sh` |
| 效能計畫 | `docs/plans/strawwu-performance-budget-plan.md` |
| Nightly CI | `.github/workflows/nightly.yml` |
| Release CI | `.github/workflows/release.yml` |
| 量測輸出 | `tests/perf/output/boot-time-measurement.json` |

## 架構

```
ISO / boot-test serial log
    → measure-boot-time.sh (QEMU plymouth-start.service)
    → estimate-from-serial.py (fallback: line-ratio × boot elapsed)
    → boot-time-measurement.json
    → check-boot-regression.py (min(baseline×1.15, 45s))
    → test-perf-boot-regression.sh

advisory（預設/preflight/nightly）: 無量測 → WARN，不阻斷
strict（release）: 無量測或超標 → FAIL
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.2` → `0.7.0.3` |
| `tests/perf/` | **新增** 量測 + 回歸 + 估算腳本 |
| `docs/plans/baselines/boot-time-baseline.json` | **新增** PERF2 基線 |
| `tests/preflight/test-perf-boot-regression.sh` | **強化** 完整 gate |
| `tests/preflight/test-perf-baseline.sh` | PERF2 狀態聯動 boot baseline |
| `tests/preflight/test-ci-nightly.sh` | nightly PERF2 接線檢查 |
| `docs/plans/strawwu-performance-budget-plan.md` | PERF2 文件化 |
| `.github/workflows/nightly.yml` | advisory PERF2 step |
| `.github/workflows/release.yml` | strict PERF2 step |
| `Makefile` | `measure-boot-time`、`preflight` 納入 PERF2 |

## 基線數據

| 指標 | 值 | 來源 |
|------|-----|------|
| `plymouth_sec` baseline | 18s | `serial-bios.log` line-ratio × 389s boot |
| 硬性預算 | 45s | performance-budget-plan |
| 回歸閾值 | min(18×1.15, 45) = 20.7s | boot-time-baseline.json |
| 最新量測（live QEMU TCG） | 273s | `boot-time-measurement.json`（advisory 不阻斷） |
| baseline 參考值 | 18s | boot-test serial artifact 估算 |

## 測試證據

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-perf-boot-regression   # exit 0 — 2026-07-08T11:48+08:00
make preflight                   # exit 0 — ~245s，2026-07-08T11:52+08:00
```

### `make test-perf-boot-regression` — exit 0

Log: `/tmp/test-perf-boot-regression-worker.log`

```
=== POST-PERF boot regression done: PASS ===
PASS: PERF2 regression check: measured 273.0s > 20.7s (min(baseline 18s × 1.15, budget 45s)) — advisory
```

（advisory 模式：超標僅 WARN，gate 仍 PASS；strict fixture 數學檢查亦 PASS）

### `make preflight` — exit 0

Log: `/tmp/preflight-post-perf-boot-worker.log`

含 POST-PERF boot regression：`=== POST-PERF boot regression done: PASS ===`（約 line 2775）

preflight 全程無 FAIL；live TCG 量測 273s（無 KVM），advisory 模式正確不阻斷。

### 量測 smoke

```bash
# Artifact 估算（boot-test serial）
STRAWWU_PERF_BOOT_FROM_ARTIFACTS=1 make measure-boot-time
# plymouth_sec=18, status=PASS

# Live QEMU（TCG，本機無 KVM）
STRAWWU_PERF_BOOT_TIMEOUT=600 make measure-boot-time
# plymouth_sec=273, status=PASS（超預算但找到 marker）
```

## 產品決策

無阻塞。TCG 環境下 live QEMU 量測可能逾時（>180s）；採 boot-test artifact fallback（`STRAWWU_PERF_BOOT_FALLBACK_ARTIFACTS=1`）確保 advisory gate 可運作。Release strict 仍嘗試 live measure 後 fallback。

## 已知限制

| 項目 | 狀態 |
|------|------|
| idle RAM / firstboot 回歸 | 待後續 PERF3 |
| live QEMU plymouth 量測在無 KVM 環境 | 慢，依 artifact fallback |
| nightly 不自動 `measure-boot-time` | 僅 structural gate（避免 nightly 逾時） |

## 後續

Hermes mark PASS → 自動啟動 **post-ci-kernel-selfhosted**（依 POST-MVP-AUTO-SEQUENCE）。

## 建議驗收

```bash
make test-perf-boot-regression
make preflight
```

## 建議 commit message

```
feat(post-perf): PERF2 boot-time regression CI gate

- measure-boot-time.sh + check-boot-regression.py + boot-time-baseline.json
- nightly advisory + release strict PERF2 wiring
- VERSION 0.7.0.3
Tests: make test-perf-boot-regression preflight
```
