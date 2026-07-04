# Wave 0 — Preflight 基線建立

| 任務 ID | W0-baseline |
|---------|-------------|
| 版本 | 1.0 |
| 日期 | 2026-07-04 |
| 狀態 | PASS（2026-07-04） |

## 目標

建立 12 份 Wave 0 preflight 腳本與 3 份 baseline JSON，作為 v4 總計畫後續 Wave 1–8 的量化起點。

## 範圍

### 必須交付

1. `tests/preflight/lib/common.sh`
2. 12 支 preflight 腳本（N0/F0/D0/R0/RE0/SEC0/LEG0/OBS0/PERF0/CI0/W0 + 聚合 runner）
3. `docs/plans/baselines/release-baseline.json`
4. `docs/plans/baselines/obs-baseline.json`
5. `docs/plans/baselines/perf-baseline.json`
6. Makefile target `test-wave0-baseline`
7. `docs/plans/stage-reports/W0-baseline-report.md`

### 必讀

- `docs/plans/strawwu-ai-worker-sop.md`
- `docs/plans/strawwu-prd-v0.5.md`
- `docs/plans/README.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-wave0-baseline
# exit 0
```

三份 baseline JSON 必須存在且 `python3 -m json.tool` 合法。

## 禁止

- 修改 `kernel/` 源碼
- `SKIP_SQUASHFS=1` 並行 boot-test
- 同一 ISO 並行改動
- purge rootfs 套件（Wave 1 才做）

## 證據路徑

- 測試輸出：終端 stdout
- 基線 JSON：`docs/plans/baselines/*.json`
- 階段報告：`docs/plans/stage-reports/W0-baseline-report.md`

## 完成後

Hermes mark PASS → 啟動 Wave 1（B1 purge + F1 Flathub + F2 nosnap + S1 initrd 依序，不並行）。
