# StrawWU initrd / 開機鏈自製化計畫

| 代號 | S0–S5 | Wave | W0,W1,W8 |
|------|-------|------|----------|

## 策略

initrd-splice 保留 `main.zst`；逐步 fork casper → `strawwu-live-init`；內部保留 `username=ubuntu` / `ID=ubuntu`。

## Phase 摘要

S0 盤點 · S1 低風險替換（live-shutdown、iso-scan） · S2 fork casper 核心 · S3 casper-bottom → strawwu-live-bottom · S4 deb hooks · S5 kernel IPC 服務化 · **S6 dracut 遷移準備（v4）**

## 現況 ~15%

boot-selfcheck、Plymouth、early3 splice 已有；34 casper-bottom 未替換。

## 完整規格

Hermes: `strawwu-initrd-ubuntu-services-plan-2026-07-04.html`
