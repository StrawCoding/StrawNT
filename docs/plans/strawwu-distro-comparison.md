# StrawWU 發行版策略對照

| 版本 | 2.0 |
|------|-----|
| 日期 | 2026-07-06 |
| 基線 | **Ubuntu 26.04 LTS Resolute Raccoon** |

## 五級策略（Tier 0–4）

| Tier | 策略 | 代表 |
|------|------|------|
| 0 | 只改 squashfs | 初學 remix |
| 1 | patch casper.conf / GRUB | Mint、Zorin、neon |
| 2 | initrd 局部 + rebrand | Pop!_OS、**StrawWU 現況（noble）** |
| 3 | live-build + casper shim | elementary |
| 4 | dracut / from-scratch | **Ubuntu 26.04 遷移目標** |

## StrawWU 定位

Tier 2→3 過渡；MVP 在 noble 24.04.2 完成後，**u26 遷移管線**升級至 Resolute 26.04。

## 長任務管線

| Track | 段數 | 終點 |
|-------|------|------|
| Wave MVP | 47 | `w8-mvp-closeout` |
| Ubuntu 26.04 | 7 | `u26-m7-closeout` |
| Post-MVP | 14 | `post-v09-engineering-closeout` |

## 完整報告

Hermes: `strawwu-distro-comparison-v5-2026-07-06.html`
