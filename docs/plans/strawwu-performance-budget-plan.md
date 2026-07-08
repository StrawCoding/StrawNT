# StrawWU 效能 / 體積預算計畫

| 代號 | PERF0–PERF2 |
|------|-------------|
| 版本 | 0.7.0.3（PERF2 開機回歸） |

## 缺口

release ISO 6.1GB 無正式預算；開機時間基線已納入 PERF2 gate。

## 預算（v0.5 草案）

| 指標 | 目標 | Gate |
|------|------|------|
| release-iso 大小 | ≤7GB（xz） | PERF1 strict（release） |
| Live 開機至 Plymouth | ≤45s QEMU | PERF2 strict（release） |
| 安裝後 idle RAM | ≤2.5GB | 待量測（PERF3） |
| firstboot 完成 | ≤3min | 待量測（PERF3） |

## Phase

| 代號 | 說明 | 狀態 |
|------|------|------|
| PERF0 | 基線腳本 + `perf-baseline.json` | complete |
| PERF1 | ISO size gate in CI | complete |
| PERF2 | boot-time regression（Plymouth 里程碑 + 15% 回歸閾值） | complete |

## PERF2 boot-time regression

### 量測

- 腳本：`tests/perf/measure-boot-time.sh`
- QEMU BIOS、`kvm:tcg`、4GiB RAM、serial 輪詢 `plymouth-start.service`
- 輸出：`tests/perf/output/boot-time-measurement.json`

### 基線與閾值

- 基線 JSON：`docs/plans/baselines/boot-time-baseline.json`
- 硬性預算：45s（`live_boot_to_plymouth_max_sec`）
- 回歸比率：1.15（相對 baseline `plymouth_sec`）
- 有效閾值：`min(baseline × 1.15, 45s)`

### Gate 模式

| 模式 | 環境變數 | 行為 |
|------|----------|------|
| advisory | `STRAWWU_PERF2_GATE=advisory`（預設） | 無量測或超標 → WARN，不阻斷 preflight/PR |
| strict | `STRAWWU_PERF2_GATE=strict` | 無量測或超標 → FAIL（release / nightly 可選） |

### CI 接線

- **nightly.yml**：dev-iso 建置後 `STRAWWU_PERF2_GATE=advisory make test-perf-boot-regression`
- **release.yml**：boot-test 後 `STRAWWU_PERF2_GATE=strict make test-perf-boot-regression`
- **preflight**：`make test-perf-boot-regression`（advisory）

### 驗收命令

```bash
make test-perf-boot-regression
make preflight
```

## Wave

W0 基線 · W7 RE 管線整合 gate · Post-MVP PERF2
