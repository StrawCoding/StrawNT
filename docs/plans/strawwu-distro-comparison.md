# StrawWU 發行版策略對照

| 版本 | 1.0 |
|------|-----|
| 日期 | 2026-07-04 |

## 五級策略（Tier 0–4）

| Tier | 策略 | 代表 |
|------|------|------|
| 0 | 只改 squashfs | 初學 remix |
| 1 | patch casper.conf / GRUB | Mint、Zorin、neon |
| 2 | initrd 局部 + rebrand | Pop!_OS、**StrawWU 現況** |
| 3 | live-build + casper shim | elementary |
| 4 | dracut / from-scratch | Ubuntu 26.04 方向 |

## StrawWU 定位

Tier 2→3 過渡：initrd splice + 自製 deb 管線 + Windows compat 獨有。

## 完整報告

Hermes: `strawwu-ubuntu-kernel-distros-comparison-2026-07-04.html`
