# StrawWU Wave 鎖序（自動接續）

| 版本 | 2.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 權威文件 | **`kickoff/WAVE-AUTO-SEQUENCE.md`**（47 段 · Wave 0→8） |

## 摘要

- **47 段**全自動鎖序：`w0-baseline` → … → `w8-mvp-closeout`
- 配置：`~/.hermes/config/task-workers/projects/strawwu.json` → `wave_locked_sequence`
- PASS 路由：`longtask_transition_dispatch.sh`（wave stage → `longtask_wave_transition_next.sh`）
- 進度 JSON：`docs/plans/baselines/wave-status.json`
- 全 PASS 驗證：`make test-wave-all-pass`

## Wave 分組

| Wave | 段數 | 終點 stage |
|------|------|------------|
| W0 | 1 | w0-baseline |
| W1 | 4 | w1-s1-initrd |
| W2 | 5 | w2-trust-baseline |
| W3 | 5 | w3-w0-wincompat-baseline |
| W4 | 6 | w4-l10n-ime |
| W5 | 8 | w5-grt-session |
| W6 | 8 | w6-doc1-user-docs |
| W7 | 4 | w7-perf-legal-gate |
| W8 | 6 | w8-mvp-closeout |

## 基礎設施修正（2026-07-04）

1. `longtask_transition_dispatch.sh` — supervisor 不再誤用 phase transition
2. `task_worker_lib.next_eligible_stage` — wave 未完成時優先 wave 鎖序
3. Webhook / supervisor prompt 已對齊 dispatch

## 監看

```bash
python3 ~/.hermes/scripts/hermes_task_worker.py watch strawwu
make test-wave-all-pass
tmux attach -t ltask-strawwu-w1-b1-purge
```
