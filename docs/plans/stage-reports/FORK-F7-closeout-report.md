# FORK-F7-closeout — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `fork-f7-closeout` |
| 版本 | `0.6.2.6`（`0.6.2.5` → `0.6.2.6`） |
| 基底 | Ubuntu 26.04 **resolute** fork（預設 `base_mode=fork`） |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-07T23:58+08:00（worker fork-f7-closeout 驗證） |

## 摘要

完成 Fork 基底遷移 **closeout**：將 `ubuntu-base-target.json` 的 `base_mode` 從 `clone` 切換為 **`fork` 預設**；`fork-base/manifest.json` 標記 `status=active`；新增 fork DoD、HTML 報告（hermes-deliver Teal 深色主題）與 `test-fork-f7-closeout` / `validate-fork-closeout.py` gate。全 7 段 fork 遷移狀態寫入 `fork-status.json`。

## 交付物

| 類型 | 路徑 |
|------|------|
| DoD | `docs/plans/fork-closeout/fork-dod.md` |
| HTML 報告 | `docs/plans/fork-closeout/html/fork-closeout-report.html` |
| HTML 渲染器 | `tests/fork-closeout/render-html.py` |
| 驗證器 | `tests/fork-closeout/validate-fork-closeout.py` |
| Preflight gate | `tests/preflight/test-fork-f7-closeout.sh` |
| Baseline | `docs/plans/baselines/fork-closeout-baseline.json` |
| 基底配置 | `docs/plans/ubuntu-base-target.json`（`base_mode=fork`） |
| Fork 狀態 | `docs/plans/baselines/fork-status.json`（7/7 PASS） |
| Manifest | `os-image/fork-base/manifest.json`（`status=active`） |

## 架構

```
ubuntu-base-target.json (base_mode: fork)
        │
        ▼ make sync-base  → fork-sync-base.sh
   .fork-sync-base-ok + fork snapshot rootfs
        │
        ▼ make release-iso
   StrawWU-<VERSION>-amd64.iso
        │
        ▼ fork-f7 closeout
   fork-status.json 7/7 PASS + HTML hermes-deliver
        │
        ▼ 自動啟動
   post-d1-strawwu-drivers
```

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.2.5` → `0.6.2.6` |
| `hub/package.json` | 版本同步 |
| `components/Cargo.toml` | 版本同步 |
| `docs/plans/ubuntu-base-target.json` | **base_mode=fork** |
| `docs/plans/baselines/fork-status.json` | F5–F7 → PASS |
| `os-image/fork-base/manifest.json` | status=active |
| `docs/plans/fork-closeout/fork-dod.md` | **新增** DoD |
| `tests/fork-closeout/render-html.py` | **新增** HTML 渲染 |
| `tests/fork-closeout/validate-fork-closeout.py` | **新增** closeout 驗證 |
| `tests/preflight/test-fork-f7-closeout.sh` | **新增** preflight gate |
| `Makefile` | test-fork-f7-closeout、preflight 鏈 |

## 驗證命令輸出

### `make test-fork-f7-closeout` — exit 0（~0.5s）

Log: `/tmp/fork-f7-closeout-test.log`

```
PASS: ubuntu-base-target.json base_mode=fork
PASS: fork-base manifest status=active
PASS: STRAWWU_BASE_MODE resolves to fork
PASS: rendered docs/plans/fork-closeout/html/fork-closeout-report.html
PASS: HTML Teal theme + hermes-deliver marker
PASS: frozen fork-status.json all stages PASS
=== Fork closeout validation: PASS ===
```

### `make test-fork-all-pass` — exit 0（~0.1s）

Log: `/tmp/fork-f7-all-pass-test.log`

```
PASS: all 7 fork stages PASS
FORK ALL-PASS OK
```

### `make preflight` — exit 0（~200s）

Log: `/tmp/fork-f7-preflight.log`

```
（全 53 靜態 gate PASS，含 test-fork-f7-closeout 鏈尾）
=== FORK-F7 closeout done: PASS ===
EXIT:0
```

## 工作區狀態

- 變更尚未 commit（待 Hermes commit + push）
- 建議 Hermes 執行 `trigger-verify` 複驗後 mark PASS

## 測試摘要

| 命令 | exit | 耗時 | log |
|------|------|------|-----|
| `make test-fork-f7-closeout` | 0 | ~0.5s | `/tmp/fork-f7-closeout-test.log` |
| `make test-fork-all-pass` | 0 | ~0.1s | `/tmp/fork-f7-all-pass-test.log` |
| `make preflight` | 0 | ~200s | `/tmp/fork-f7-preflight.log` |

## 建議 commit message

```
feat(fork-f7): set base_mode=fork default + closeout HTML report

- Switch ubuntu-base-target.json base_mode to fork
- Add fork-dod, render-html, validate-fork-closeout gate
- Mark fork-base manifest active; fork-status 7/7 PASS
Tests: make test-fork-f7-closeout; make test-fork-all-pass; make preflight
```

## 後續

`fork-f7-closeout` PASS → Hermes 自動 launch **post-d1-strawwu-drivers**。
