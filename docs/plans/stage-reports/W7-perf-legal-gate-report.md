# W7 PERF+LEGAL gate 階段報告

| 任務 | w7-perf-legal-gate |
|------|-------------------|
| 版本 | 0.5.0.3 |
| 日期 | 2026-07-06 |
| Worker | 階段 41/47（w7-perf-legal-gate） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |
| 最後驗證 | 2026-07-06T00:35 UTC-4（本 worker 重跑三項命令 + preflight 重驗） |

## 目標

建立 **PERF1 ISO 體積 gate** 與 **LEG4 release 合規 gate**，納入 CI/Release workflow，對齊 `strawwu-performance-budget-plan.md` 與 `strawwu-legal-compliance-plan.md`。

## 交付物

| 類型 | 路徑 |
|------|------|
| PERF0+PERF1 preflight | `tests/preflight/test-perf-baseline.sh`（強化 + perf-baseline.json） |
| LEG4 CI wiring gate | `tests/preflight/test-perf-legal-gate.sh` |
| LEG2 baseline 更新 | `tests/preflight/test-legal-trademark.sh`（phases 結構） |
| PR gate workflow | `.github/workflows/ci.yml`（`perf-legal-gate` job） |
| Release gate workflow | `.github/workflows/release.yml`（strict PERF1 + LEG4 after ISO build） |
| baseline JSON | `docs/plans/baselines/perf-baseline.json`、`legal-baseline.json`、`ci-baseline.json` |
| Makefile | `test-perf-baseline`、`test-perf-legal-gate`；`preflight` 含本階段 |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **PERF1 size gate** | `STRAWWU_PERF_GATE=strict` 時 ISO >7GB 或無 ISO → FAIL；預設 `advisory` 供 PR/preflight |
| **test-perf-baseline** | 量測 `os-image/output` 最新 ISO + squashfs；寫入 `perf-baseline.json` phases PERF0/PERF1 |
| **LEG4 compliance** | `ci.yml` 獨立 job：`test-perf-baseline` + `test-legal-trademark`；`release.yml` ISO 建置後 strict PERF1 + LEG4 |
| **test-perf-legal-gate** | 驗證 workflow/Makefile 接線；隔離 stub ISO（64MiB pass / 7.5GiB fail）；更新 legal/ci baseline |
| **隱私/EULA** | 維持 W2 LEG2：privacy.html / eula.html 含「無預設遙測」「opt-in」；opt-in 統計後端留 v1.0 |

### Release 管線 gate 位置（摘要）

```
release-iso
  → preflight-iso-before-boot
  → STRAWWU_PERF_GATE=strict make test-perf-baseline   # PERF1
  → make test-legal-trademark                          # LEG4
  → release-sign + manifest
```

### PR gate（ci.yml 新增 job）

```
perf-legal-gate:
  make test-perf-baseline && make test-legal-trademark
```

## 驗收命令輸出

### `make test-perf-baseline` — exit 0

Log: `/tmp/w7-perf-test-perf-baseline.log`

```
=== PERF0+PERF1 perf-baseline preflight ===
PASS: PERF gate mode=advisory
PASS: latest ISO size bytes=5357494272 (4.99 GB)
PASS: PERF1 ISO size within 7GB budget (4.99 GB)
=== PERF0+PERF1 perf-baseline done: PASS ===
```

### `make test-legal-trademark` — exit 0

Log: `/tmp/w7-perf-test-legal-trademark.log`

```
=== LEG2 legal-trademark preflight ===
（全項 PASS：商標掃描、privacy/eula、無預設遙測條款）
=== LEG2 legal-trademark done: PASS ===
```

### `make preflight` — exit 0（~227s，重驗）

Log: `/tmp/w7-perf-preflight-rerun.log`

含 W0–W7 全部階段 + **PERF0+PERF1** + **W7 PERF+LEGAL gate** 終行：`=== W7 PERF+LEGAL gate done: PASS ===`

## 變更檔案清單

```
VERSION (0.5.0.2 → 0.5.0.3)
Makefile
.github/workflows/ci.yml
.github/workflows/release.yml
tests/preflight/test-perf-baseline.sh                              (PERF0→PERF1 強化)
tests/preflight/test-perf-legal-gate.sh                            (新增)
tests/preflight/test-legal-trademark.sh                          (LEG phases 結構)
tests/preflight/test-ci-baseline.sh                              (新 targets)
tests/preflight/test-ci-nightly.sh                               (ci.yml gate 檢查)
docs/plans/baselines/perf-baseline.json                            (PERF1 phases)
docs/plans/baselines/legal-baseline.json                           (LEG4 complete)
docs/plans/baselines/ci-baseline.json                              (perf_legal_gates)
docs/plans/stage-reports/W7-perf-legal-gate-report.md              (本檔)
```

## 技術備註（治本）

1. **雙模式 PERF gate**：日常 preflight/PR 用 `advisory`（無 ISO 或超標僅 WARN）；release tag 用 `strict` 硬性阻斷超 7GB ISO。
2. **隔離測試不污染 baseline**：`STRAWWU_OUTPUT_DIR` 設定時跳過 JSON 寫入；`test-perf-legal-gate` 結束後 refresh 真實 ISO 量測。
3. **LEG4 不重複 LEG2 內容檢查**：`test-legal-trademark` 維持商標/法律文件掃描；`test-perf-legal-gate` 專責 CI workflow 接線 + baseline 狀態。
4. **ci.yml 與 preflight 互補**：preflight 已含 legal；獨立 `perf-legal-gate` job 讓 PR 可並行、失敗定位更清楚。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| PERF2 boot-time / idle RAM / firstboot 回歸 | 待量測基線後實作 |
| LEG1 license-inventory.csv 自動產生 | deferred |
| LEG3 Calamares/GRUB/Plymouth 合規審計 | deferred |
| opt-in 統計後端 | v1.0（deferred-scope §3） |
| nightly.yml PERF strict gate | 僅 dev-iso，不強制 strict（體積預算針對 release-iso xz） |

## VERSION

`0.5.0.2` → `0.5.0.3`（`bash scripts/bump-version.sh iterate`）

## 建議 commit message

```
feat(w7): PERF1 ISO size gate + LEG4 release compliance CI

- PERF1: test-perf-baseline strict/advisory modes (7GB budget)
- LEG4: test-perf-legal-gate + ci.yml/release.yml wiring
- Update perf/legal/ci baseline JSON phases
- VERSION 0.5.0.3
Tests: make test-perf-baseline test-legal-trademark preflight PASS
```

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-perf-baseline
make test-legal-trademark
make preflight
```

## 下一階段

**w8-hw-matrix**（Hermes mark PASS 後自動啟動，勿問使用者）。

## Hermes 標記

（留空，由 Hermes 填寫 PASS/FAIL 與時間戳）
