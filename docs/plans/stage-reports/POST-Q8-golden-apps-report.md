# POST-Q8-golden-apps — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-q8-golden-apps` |
| 版本 | `0.7.0.8`（`0.7.0.7` → `0.7.0.8`） |
| 版本目標 | `0.9.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T13:13+08:00 |
| Worker 回合 | 階段 1/8（post-q8-golden-apps）— 實作完成並重跑驗證 |

## 摘要

完成 Post-MVP **Q8 黃金應用啟動驗證**（Office / Steam / Epic / 三角洲 launcher）：

- 新增 `strawwu-runtime::golden_apps` 模組與 `golden-apps-verify` CLI
- 新增 `tests/wincompat/run-golden-apps-verify.sh`：cargo test → LaunchProbeEngine → 合併 `compat-matrix.json`
- 強化 `tests/preflight/test-golden-apps.sh` 完整 gate
- 產出誠實 **PARTIAL** 等級（啟動器 B、Office C），**禁止宣稱登入/遊玩/完整辦公**

## 交付物

| 類型 | 路徑 |
|------|------|
| Golden apps 模組 | `components/strawwu-runtime/src/golden_apps.rs` |
| Verify CLI | `components/strawwu-runtime/src/bin/golden_apps_verify.rs` |
| 規格 | `components/specs/golden-apps-launch.md` |
| 清單 | `components/tests/wincompat/golden-apps.json` |
| 驗證腳本 | `tests/wincompat/run-golden-apps-verify.sh` |
| Smoke 腳本 | `tests/wincompat/test-golden-apps.sh` |
| Preflight gate | `tests/preflight/test-golden-apps.sh` |
| Compat matrix | `components/tests/wincompat/output/compat-matrix.json` |
| 證據 JSON | `components/tests/wincompat/output/golden-apps-launch.json` |
| Baseline | `docs/plans/baselines/golden-apps-launch-baseline.json` |

## 架構

```
cargo test -p strawwu-runtime golden_apps (6 tests)
        │
        ▼
golden-apps-verify CLI
        │ LaunchProbeEngine per golden-apps.json
        ▼
golden-apps-launch.json
        │
        ▼ merge
compat-matrix.json → golden_apps_matrix.cases[]
  ├─ launch_verified: true
  ├─ evidence.probes[] (per-probe pass/fail)
  └─ status: PARTIAL (never PASS)
```

## Q8 決策對照

| 決策 | 實作 |
|------|------|
| Office 可啟動、基本文件操作 | COM stub + VFS doc open 探測；grade C |
| Steam/Epic 啟動器 | cooperation + IPC + launcher window；grade B |
| 三角洲僅啟動器 | 同啟動器探測集；不驗遊戲/反作弊連線 |
| 禁宣稱遊玩/登入 | 所有 case status≠PASS；overall=PARTIAL |
| native 共享 SubsystemSession | 所有 profile backend=native, session_mode=shared |

## 黃金應用矩陣結果（誠實 PARTIAL）

| App | Scope | Grade | Status | Probe Pass |
|-----|-------|-------|--------|------------|
| `office` | launch_and_basic_edit | C | PARTIAL | 5/5 |
| `steam-launcher` | launcher_only | B | PARTIAL | 6/6 |
| `epic-launcher` | launcher_only | B | PARTIAL | 6/6 |
| `delta-force-launcher` | launcher_only | B | PARTIAL | 6/6 |

> 探測為 in-process LaunchProbeEngine（stub PE + GUI smoke + IPC/cooperation）。無實機 Office/Steam/Epic/三角洲二進位；實機擴充留待 Hermes physical session。

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.7` → `0.7.0.8` |
| `components/strawwu-runtime/src/golden_apps.rs` | **新增** launch 探測模組 |
| `components/strawwu-runtime/src/bin/golden_apps_verify.rs` | **新增** CLI |
| `components/strawwu-runtime/Cargo.toml` | chrono + binary target |
| `components/strawwu-runtime/src/lib.rs` | 匯出 golden_apps |
| `components/specs/golden-apps-launch.md` | **新增** Q8 規格 |
| `components/tests/wincompat/golden-apps.json` | 版本 bump |
| `tests/wincompat/run-golden-apps-verify.sh` | **新增** 驗證管線 |
| `tests/wincompat/test-golden-apps.sh` | 實作 smoke gate |
| `tests/preflight/test-golden-apps.sh` | 強化 preflight gate |

## 測試證據

### `make test-golden-apps`（exit 0）

```
PASS: golden apps evidence 4/4 launch_verified
PASS: honest PARTIAL grades (no PASS claims)
  - office: grade=C status=PARTIAL probes=5/5
  - steam-launcher: grade=B status=PARTIAL probes=6/6
  - epic-launcher: grade=B status=PARTIAL probes=6/6
  - delta-force-launcher: grade=B status=PARTIAL probes=6/6
=== POST-Q8 golden apps done: PASS ===
```

完整 log：`/tmp/post-q8-test-golden-apps.log`

### `make preflight`（exit 0）

```
=== POST-V06 closeout done: PASS ===
（全 preflight 腳本鏈 exit 0，含 test-hw-t3-wincompat、test-anticheat-substantive 等）
```

完整 log：`/tmp/post-q8-preflight.log`（約 247s，3107 行，exit 0）

## 已知限制 / 非阻塞

1. **無實機二進位**：CI 以 LaunchProbeEngine 模擬；Hermes 可追加 physical smoke。
2. **不得宣稱 grade A**：完整生產啟動/登入保留給未來實機 golden-app 驗證。
3. **三角洲反作弊**：本 stage 僅 launcher 探測，不驗遊戲本體與 AC 連線（對齊 Q8 決策）。

## 阻塞項

無產品決策阻塞。

## 建議 Hermes

- 執行 `make test-golden-apps` + `make preflight` trigger-verify
- 可選：實機 session 對照 `tests/hw/smoke-wincompat.sh` 擴充 golden-app 維度

## 下一階段

| 項目 | 說明 |
|------|------|
| 下一 Post-MVP stage（POST-HW5-stable-gate） | Hermes PASS 後自動啟動 |
