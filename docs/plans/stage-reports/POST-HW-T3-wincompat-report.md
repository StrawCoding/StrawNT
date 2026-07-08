# POST-HW-T3-wincompat — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-hw-t3-wincompat` |
| 版本 | `0.7.0.7`（`0.7.0.6` → `0.7.0.7`） |
| 版本目標 | `0.8.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T12:51+08:00 |
| Worker 回合 | 階段 1/8（本回合驗收重跑） |

## 摘要

實作 POST-HW-T3 Windows compat / 遊戲路徑 HW smoke 基礎設施：`smoke-wincompat.sh`（status + GUI notepad + compat-matrix 6.6/anticheat 探測）、`run-hw-t3-wincompat.sh`（fixture merge runner）、完整 preflight gate，並合併 **誠實 PARTIAL** T3 矩陣條目至 `hw-matrix-results.json`。納入 `make preflight` 鏈。

## 交付物

| 類型 | 路徑 |
|------|------|
| Smoke 腳本 | `tests/hw/smoke-wincompat.sh` |
| Matrix runner | `tests/hw/run-hw-t3-wincompat.sh` |
| Preflight gate | `tests/preflight/test-hw-t3-wincompat.sh` |
| Baseline | `docs/plans/baselines/hw-t3-wincompat-baseline.json` |
| 矩陣結果 | `docs/plans/hw-matrix-results.json`（9 台，t3_wincompat=1） |
| Makefile | `test-hw-t3-wincompat` + `test-hw-t3-wincompat-run` + preflight 鏈 |

## T3 wincompat 矩陣 profile（1/1 fixture PARTIAL）

| machine_id | environment | wincompat_status | wincompat_gui | wincompat_game | wincompat_aggregate |
|------------|-------------|------------------|---------------|----------------|---------------------|
| `t3-wincompat-nvidia-desktop` | fixture | PASS | PASS | PARTIAL | PARTIAL |

> Worker 環境無實體 dGPU 遊戲二進位，以 `strawwu run notepad.exe` GUI smoke + compat-matrix anticheat overall=PARTIAL 建立條目。Hermes 可於 NVIDIA 桌面以 `--environment physical-installed --no-fixture` 覆寫（仍預期 game=PARTIAL 除非實機 ranked 遊戲 PASS）。

## 變更檔案

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.7.0.6` → `0.7.0.7` |
| `tests/hw/smoke-wincompat.sh` | **新增** T3 wincompat smoke 輸出 JSON entry |
| `tests/hw/run-hw-t3-wincompat.sh` | **新增** fixture merge runner + t3_wincompat 摘要 |
| `tests/preflight/test-hw-t3-wincompat.sh` | 擴充完整 gate（原 stub 僅查 entries 鍵） |
| `docs/plans/hw-matrix-results.json` | 合併 `t3-wincompat-nvidia-desktop` + wave/dimensions/t3_wincompat |
| `Makefile` | preflight 鏈納入 hw-t3 gate；新增 `-run` target |
| `docs/plans/baselines/hw-t3-wincompat-baseline.json` | 新增 baseline |

## 誠實邊界

1. **Fixture 模式**：worker 以 cargo-built `strawwu` CLI 模擬 status/GUI smoke；非 Live USB / 已安裝 OS session 證據。
2. **game=PARTIAL**：compat-matrix 6.6 cargo PASS 但 anticheat overall=PARTIAL；Q7 驗收=可正常運行，非 ranked/官方 AC 簽章 PASS。
3. **無實機 Steam/Epic/三角洲**：Q8 launcher 實機 smoke 留待 Hermes physical session 或 POST-Q8-golden-apps。
4. **矩陣相容**：T3 條目標記 `live_boot/wifi/gpu_driver/suspend/hidpi=SKIP`，不影響既有 T1/T2 計數。

## 驗證命令輸出

### `make test-hw-t3-wincompat-run` — exit 0

Log: `/tmp/post-hw-t3-matrix-run.log`

```
==> POST-HW-T3 wincompat smoke OK (aggregate=PARTIAL, fixture=1)
PASS: merged T3 wincompat matrix entries 1
==> POST-HW-T3 wincompat matrix complete → docs/plans/hw-matrix-results.json
```

### `make test-hw-t3-wincompat` — exit 0

Log: `/tmp/post-hw-t3-preflight.log`

```
PASS: T3 wincompat entries 1 (gui+status PASS, game PARTIAL=1)
PASS: profiles=t3-wincompat-nvidia-desktop
=== POST-HW-T3 wincompat done: PASS ===
```

### `make preflight` — exit 0（244s）

Log: `/tmp/post-hw-t3-preflight-full.log`

```
=== POST-HW-T3 wincompat preflight ===
...
=== POST-HW-T3 wincompat done: PASS ===
...
EXIT:0
```

> 本回合 2026-07-08T12:47–12:51+08:00 重跑；全鏈 3103 行、exit 0。

## Hermes 實機 workflow

```bash
# 於已安裝 StrawWU dGPU session 內
bash tests/hw/smoke-wincompat.sh \
  --environment physical-installed \
  --gpu-vendor nvidia \
  --machine-id t3-wincompat-nvidia-desktop \
  --output /tmp/smoke-wincompat.json
bash tests/hw/merge-entry.sh --entry /tmp/smoke-wincompat.json
```

## 建議 commit message

```
feat(post-hw): add T3 wincompat HW smoke matrix (honest PARTIAL)

- Add smoke-wincompat.sh + run-hw-t3-wincompat.sh (fixture path)
- Expand test-hw-t3-wincompat.sh gate; add to preflight chain
- Merge t3-wincompat-nvidia-desktop into hw-matrix-results.json
Tests: make test-hw-t3-wincompat-run PASS, make test-hw-t3-wincompat, make preflight
Issue: v0.7.0.7
```

## 待辦

| 項目 | 負責 |
|------|------|
| Hermes mark PASS | Hermes |
| 實機 dGPU 遊戲/launcher smoke 覆寫 | Hermes physical session |
| 下一 Post-MVP stage（POST-Q8-golden-apps） | Hermes PASS 後自動啟動 |

## Worker 時間線

| 時間 | 事件 |
|------|------|
| 2026-07-08T12:41+08:00 | 開始 POST-HW-T3 實作 |
| 2026-07-08T12:42+08:00 | VERSION bump 0.7.0.6 → 0.7.0.7 |
| 2026-07-08T12:43+08:00 | `run-hw-t3-wincompat.sh` exit 0，t3_wincompat=1 |
| 2026-07-08T12:49+08:00 | 前序 worker 初版驗收 exit 0 |
| 2026-07-08T12:47+08:00 | 本 worker 接手 companion IN_PROGRESS |
| 2026-07-08T12:47+08:00 | `make test-hw-t3-wincompat-run` exit 0（t3_wincompat=1, aggregate=PARTIAL） |
| 2026-07-08T12:47+08:00 | `make test-hw-t3-wincompat` exit 0 |
| 2026-07-08T12:51+08:00 | `make preflight` exit 0（244s）— 待 Hermes mark PASS |
