# POST-HW-T2-installed — Stage Report

| 欄位 | 值 |
|------|-----|
| 階段 ID | `post-hw-t2-installed` |
| 版本 | `0.6.3.2`（`0.6.3.0` → `0.6.3.2`） |
| 版本目標 | `0.6.0.0-target` |
| 狀態 | **待 Hermes 驗收**（worker 不自宣稱 PASS） |
| 完成時間 | 2026-07-08T04:36+08:00 |
| Worker 回合 | 階段 1/8（Hermes TICK 複驗） |

## 摘要

實作 POST-HW-T2 安裝後 smoke 基礎設施：Calamares 安裝 → 注入 `strawwu-t2-installed-smoke.service` → 已安裝磁碟 UEFI 開機 → 收集 suspend×3 + HiDPI serial markers → 合併 T2 矩陣條目。新增 `smoke-installed.sh`（Hermes 實機 workflow）、`run-hw-t2-installed.sh`（worker runner）、完整 preflight gate，並納入 `make preflight` 鏈。

## 交付物

| 類型 | 路徑 |
|------|------|
| 安裝後 smoke 腳本 | `tests/hw/smoke-installed.sh` |
| T2 矩陣 runner | `tests/hw/run-hw-t2-installed.sh` |
| Preflight gate | `tests/preflight/test-hw-t2-installed.sh` |
| Baseline | `docs/plans/baselines/hw-t2-installed-baseline.json` |
| 矩陣結果 | `docs/plans/hw-matrix-results.json`（7 台，t2_installed=1） |
| Makefile | `test-hw-t2-installed` + `test-hw-t2-installed-run` + preflight 鏈 |

## T2 矩陣 profile（1/1 PASS）

| machine_id | environment | installed_boot | suspend | hidpi |
|------------|-------------|----------------|---------|-------|
| `t2-installed-intel-laptop` | installed-e2e | PASS | PASS | PASS |

ISO：`StrawWU-0.6.2.5-amd64.iso`（VERSION=0.6.3.2 無對應 ISO，runner 自動選最新）

## 變更檔案

| 檔案 | 說明 |
|------|------|
| `VERSION` | `0.6.3.0` → `0.6.3.2` |
| `tests/hw/smoke-installed.sh` | 新增：安裝後 smoke + suspend×N + HiDPI |
| `tests/hw/run-hw-t2-installed.sh` | 新增：install→inject→boot→merge T2 entry |
| `tests/preflight/test-hw-t2-installed.sh` | 擴充完整 gate（machines 鍵 + 基礎設施檢查） |
| `tests/hw/lib.sh` | installed-e2e suspend cycle serial 推斷 |
| `docs/plans/hw-matrix-results.json` | 合併 `t2-installed-intel-laptop` + `t2_installed` 摘要 |
| `docs/plans/baselines/hw-t2-installed-baseline.json` | 新增 baseline |
| `Makefile` | `test-hw-t2-installed-run`；preflight 鏈納入 T2 gate |

## 誠實邊界

1. **Worker 環境無實體安裝機台**：以 Calamares install-e2e + QEMU 已安裝磁碟開機建立 `installed-e2e` 條目；suspend×3 為 logind 探測循環（非真實 S3 休眠/resume）。
2. **注入服務**：worker 於已安裝 rootfs 注入 `strawwu-t2-installed-smoke.service`，並停用 `strawwu-firstboot-e2e` / `strawwu-e2e-guest-runner` 避免 race/reboot。
3. **T1 條目保留**：7 台總計（3 proxy + 3 physical-live + 1 T2 installed）。
4. **Hermes 建議**：於 Intel iGPU 筆電執行 Calamares 安裝後，以 `smoke-installed.sh --full-hw --environment physical-installed` 覆寫 `t2-installed-intel-laptop`（含真實 suspend×3 + HiDPI 150–200%）。

## 驗證命令輸出

### `make test-hw-t2-installed-run` — exit 0（406s，retry2）

Log: `/tmp/post-hw-t2-matrix-retry2.log`

```
==> T2 boot+suspend+HiDPI markers found after 230s
PASS: merged 1 T2 installed entries (t2_installed=1)
==> T2 matrix complete → docs/plans/hw-matrix-results.json
```

首次完整 run（install+ boot，6214s）因 firstboot/e2e guest race 導致 SUSPEND marker 缺失；修正 inject 後 `STRAWWU_HW_T2_SKIP_INSTALL=1` 重跑 PASS。

### `make test-hw-t2-installed` — exit 0

Log: `/tmp/post-hw-t2-preflight-final.log`

```
PASS: T2 installed smoke 1 (suspend+hidpi PASS)
PASS: profiles=t2-installed-intel-laptop
=== POST-HW-T2 installed done: PASS ===
```

### `make preflight` — exit 0（238s）

Log: `/tmp/post-hw-t2-preflight-worker.log`

```
=== POST-HW-T2 installed done: PASS ===
EXIT:0
```

### 本 worker 回合複驗（2026-07-08T04:36+08:00，階段 1/8）

| 命令 | 結果 | Log |
|------|------|-----|
| `make test-hw-t2-installed` | exit 0（0.3s） | `/tmp/post-hw-t2-worker-stage1-verify.log` |
| `make preflight` | exit 0（261s） | `/tmp/post-hw-t2-preflight-stage1.log` |

`make test-hw-t2-installed` 輸出摘要：

```
PASS: T2 installed smoke 1 (suspend+hidpi PASS)
PASS: profiles=t2-installed-intel-laptop
=== POST-HW-T2 installed done: PASS ===
```

`make preflight` 鏈內 T2 gate 輸出摘要：

```
=== POST-HW-T2 installed done: PASS ===
EXIT:0
```

## Hermes 實機 workflow

```bash
# 於已安裝 StrawWU session 內
bash tests/hw/smoke-installed.sh --full-hw \
  --environment physical-installed \
  --machine-id t2-installed-intel-laptop \
  --output /tmp/smoke-installed.json
bash tests/hw/merge-entry.sh --entry /tmp/smoke-installed.json
```

## 建議 commit message

```
feat(post-hw): add T2 installed smoke matrix (suspend×3 + HiDPI)

- Add smoke-installed.sh + run-hw-t2-installed.sh (install-e2e path)
- Expand test-hw-t2-installed.sh gate; add to preflight chain
- Merge t2-installed-intel-laptop into hw-matrix-results.json
Tests: make test-hw-t2-installed-run PASS, make test-hw-t2-installed PASS, make preflight PASS
Issue: v0.6.3.2
```

## 待辦

| 項目 | 負責 |
|------|------|
| Hermes mark PASS | Hermes |
| 真實安裝機 suspend×3 + HiDPI 覆寫 | Hermes physical session |
| 下一 Post-MVP stage | Hermes PASS 後自動啟動 |

## Worker 時間線

| 時間 | 事件 |
|------|------|
| 2026-07-08T02:04+08:00 | 開始實作 T2 基礎設施 |
| 2026-07-08T02:04+08:00 | VERSION bump 0.6.3.0 → 0.6.3.1 |
| 2026-07-08T03:47+08:00 | 首次 `test-hw-t2-installed-run`：install PASS，SUSPEND marker 缺失 |
| 2026-07-08T03:49+08:00 | 修正 inject（logind wait、停用 firstboot/e2e guest race） |
| 2026-07-08T04:19+08:00 | retry2 exit 0（230s boot，t2_installed=1） |
| 2026-07-08T04:25+08:00 | 首次 `make test-hw-t2-installed` + `make preflight` |
| 2026-07-08T04:27+08:00 | Worker 階段 1/8 續跑：複驗兩命令均 exit 0 |
| 2026-07-08T04:30+08:00 | Hermes worker-TICK companion check IN_PROGRESS |
| 2026-07-08T04:36+08:00 | 階段 1/8 TICK 複驗：`test-hw-t2-installed` + `preflight` exit 0 — 待 Hermes mark PASS |
