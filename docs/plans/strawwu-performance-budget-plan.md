# StrawWU 效能 / 體積預算計畫

| 代號 | PERF0–PERF2 |
|------|-------------|

## 缺口

release ISO 6.1GB 無正式預算；無開機時間 / 記憶體基線。

## 預算（v0.5 草案）

| 指標 | 目標 |
|------|------|
| release-iso 大小 | ≤7GB（xz） |
| Live 開機至 Plymouth | ≤45s QEMU |
| 安裝後 idle RAM | ≤2.5GB |
| firstboot 完成 | ≤3min |

## Phase

PERF0 基線腳本 · PERF1 size gate in CI · PERF2 boot-time regression

## Wave

W0 基線 · W7 RE 管線整合 gate
