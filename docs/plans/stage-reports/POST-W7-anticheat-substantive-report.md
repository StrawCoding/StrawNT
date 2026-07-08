# POST-W7-anticheat-substantive — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-w7-anticheat-substantive` |
| 版本 | `0.7.0.5`（`0.7.0.4` → `0.7.0.5`） |
| 版本目標 | `0.8.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T12:30+08:00 |
| Worker 回合 | 階段 1/8（post-w7-anticheat-substantive） |

## 摘要

完成 Post-MVP **Q7 反作弊實質等級驗證**（對照 G8 compat-matrix anticheat grade）：

- 新增 `strawwu-anticheat::substantive` 模組與 `anticheat-substantive-verify` CLI
- 新增 `tests/anticheat/run-substantive-verify.sh`：cargo test → ProbeEngine 探測 → 合併 `compat-matrix.json`
- 強化 `tests/preflight/test-anticheat-substantive.sh` 完整 gate
- 產出誠實 **PARTIAL** 等級（EAC/BE/Vanguard），**禁止宣稱完整 Win 相容或排位對戰**

## 交付物

| 類型 | 路徑 |
|------|------|
| Substantive 模組 | `components/strawwu-anticheat/src/substantive.rs` |
| Verify CLI | `components/strawwu-anticheat/src/bin/substantive_verify.rs` |
| 驗證腳本 | `tests/anticheat/run-substantive-verify.sh` |
| Preflight gate | `tests/preflight/test-anticheat-substantive.sh` |
| Compat matrix | `components/tests/wincompat/output/compat-matrix.json` |
| 證據 JSON | `components/tests/wincompat/output/anticheat-substantive.json` |
| Baseline | `docs/plans/baselines/anticheat-substantive-baseline.json` |

## 架構

```
cargo test -p strawwu-anticheat (24 tests)
        │
        ▼
anticheat-substantive-verify CLI
        │ ProbeEngine.run_probe_suite(EAC/BE/Vanguard)
        ▼
anticheat-substantive.json
        │
        ▼ merge
compat-matrix.json → anticheat_matrix.cases[]
  ├─ substantive_verified: true
  ├─ evidence.probes[] (per-probe pass/fail)
  └─ status: PARTIAL (never PASS)
```

## Q7 決策對照

| 決策 | 實作 |
|------|------|
| Q7 反作弊驗收 = 可正常運行 | ProbeEngine 探測不崩潰；誠實 PARTIAL |
| EAC native 優先 | `eac_driver_probe` backend=native, grade=B |
| BattlEye native | `battleye_init` backend=native, grade=B |
| Vanguard microvm | `vanguard_tpm_probe` backend=microvm, grade=C |
| 禁宣稱完整 Win 相容 | 所有 case status≠PASS；overall=PARTIAL |

## 反作弊矩陣結果（誠實 PARTIAL）

| Case | Backend | Grade | Status | Probe Pass |
|------|---------|-------|--------|------------|
| `eac_driver_probe` | native | B | PARTIAL | 7/9 |
| `battleye_init` | native | B | PARTIAL | 8/9 |
| `vanguard_tpm_probe` | microvm | C | PARTIAL | 6/9 |

> 探測計數含 ProbeEngine 完整 suite（AC 專屬 + WindowEnum + ProcessScan）。Vanguard TPM/核心驅動探測失敗為預期行為；整體 status 仍為 PARTIAL（非 PASS）。

## 變更檔案（主要）

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.4` → `0.7.0.5` |
| `components/strawwu-anticheat/src/substantive.rs` | **新增** substantive 證據產生 |
| `components/strawwu-anticheat/src/bin/substantive_verify.rs` | **新增** CLI |
| `components/strawwu-anticheat/Cargo.toml` | chrono + binary target |
| `components/strawwu-anticheat/src/lib.rs` | 匯出 substantive 模組 |
| `tests/anticheat/run-substantive-verify.sh` | **新增** 驗證管線 |
| `tests/preflight/test-anticheat-substantive.sh` | **強化** 完整 gate + baseline |

## 測試證據

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-anticheat-substantive   # exit 0 — 2026-07-08T12:22+08:00
make preflight                    # exit 0 — ~274s，2026-07-08T12:27+08:00
```

### `make test-anticheat-substantive` — exit 0

Log: `/tmp/post-w7-test-anticheat-substantive.log`

```
=== POST-W7 anticheat substantive preflight ===
PASS: substantive anticheat evidence 3/3
PASS: honest PARTIAL grades (no PASS claims)
PASS: anticheat-substantive baseline
=== POST-W7 anticheat substantive done: PASS ===
```

### `make preflight` — exit 0（~274s）

Log: `/tmp/post-w7-preflight.log`（`grep FAIL:` **0** 行）

## 限制與誠實聲明

1. **非實機遊戲驗證**：本階段為 ProbeEngine 整合驗證（模擬探測），非真實 EAC/BE/Vanguard 遊戲 client 實機。
2. **Vanguard grade F**：TPM attestation 與核心驅動載入無法完整模擬，policy deny 為正確行為。
3. **不得宣稱排位對戰**：compat-db grade A 保留給未來實機 golden-app 驗證；本階段最高 BattlEye grade B。
4. **Phase 6 native 預設**：EAC/BE 使用 SubsystemSession native；Vanguard 建議 microvm 覆寫。

## 後續

- Hermes mark PASS → 自動啟動 **post-hw-t3-wincompat**（依 POST-MVP-AUTO-SEQUENCE）
- 建議 Hermes trigger-verify：`make test-anticheat-substantive && make preflight`
