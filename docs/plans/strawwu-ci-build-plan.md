# StrawWU CI / Build Reproducibility 計畫

| 代號 | CI0–CI4 |
|------|---------|
| 日期 | 2026-07-04 |
| 對齊 | RE0–RE6 · GOV · Phase Q6 |

## 缺口

Mint/Pop 有 nightly CI；StrawWU 僅本地 Makefile + 長任務 worker，無正式 build farm。

## Phase

| Phase | 工作 | DoD |
|-------|------|-----|
| CI0 | 盤點現有 targets | `ci-baseline.json` |
| CI1 | chroot/deb 可重現 SOP | 同 tag 兩次 build hash 一致（rootfs 層） |
| CI2 | nightly pipeline | main cron → dev-iso + SHA256 + manifest draft |
| CI3 | PR gate | preflight + cargo test-wincompat + validate-calamares |
| CI4 | self-hosted runner PoC | Q6 文件 + 1 runner 接 RE nightly |

## 合流

RE1 manifest · GOV commit 格式 · HW0 QEMU gate
