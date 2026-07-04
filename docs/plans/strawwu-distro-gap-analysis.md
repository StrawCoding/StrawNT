# StrawWU 差距分析 — 其他發行版已改、StrawWU 尚未改

| 版本 | 3.0 |
|------|-----|
| 日期 | 2026-07-04 |
| 對齊 | 總體計畫 v4 · Wave 0–8 |

## 摘要

- **52 維度**：§A 桌面 32 · §B 發行工程 16 · §C v4 補充 4
- **已對齊/超越**：10 項（kernel、initrd、os-release、GRUB、boot-selfcheck、Phase6 cargo 367 tests）
- **明顯落後**：24 項（rootfs 22 個 ubuntu-* 套件、0 flatpak、0 strawwu deb）
- **已立項未實作**：18 項（repo 21 份計畫 + v4 補充 6 份）

## rootfs 實測（squashfs-root 2026-07-04）

| 項目 | 數量 |
|------|------|
| ubuntu-* 套件 | 22 |
| flatpak | 0 |
| strawwu-* deb | 0 |
| apport / whoopsie / ubuntu-pro / snapd | 仍在 |

## §A 桌面差距（P0）

1. purge apport/ubuntu-pro/snapd/whoopsie/ubuntu-report → B1
2. strawwu-bug-reporter → B2 + SEC2
3. strawwu-calamares-settings → I1
4. strawwu-desktop meta → D1 + B5
5. strawwu-flatpak-setup → F1（P0）
6. strawwu-update-notifier → B3
7. strawwu-firstboot + target-setup → N2–N3
8. strawwu-shell/session → D1–D2
9. **GDM greeter 品牌** → GRT0（v4 新增）
10. **fcitx5/繁中輸入預設** → L10N1（v4 新增）

## §B 工程差距

| # | 維度 | 計畫 | 狀態 |
|---|------|------|------|
| 33–35 | Release / GPG / APT | RE0–RE6 | 已立項 |
| 36–38 | SB / signing / CVE | SEC0–SEC5 | 已立項 |
| 39–40 | 法務 / Privacy | LEG0–LEG4 | 已立項 |
| 41 | 實機 HW | HW0–HW5 | 已立項 |
| 42 | Upgrade/rollback | UPG0–UPG5 | 已立項 |
| 43 | Windows Compat OS E2E | W0–W6 | 已立項 |
| 44–48 | PRD/UX/OBS/Init/GOV | 各子計畫 | 已立項 |

## §C v4 補充差距（原先漏列）

| # | 維度 | 成熟發行版 | StrawWU | 計畫 |
|---|------|-----------|---------|------|
| 49 | CI / nightly build | Pop CI、Mint buildbot | 僅本地 Makefile | CI0–CI4 |
| 50 | 使用者文件 | Mint User Guide | 僅 dev docs | DOC0–DOC3 |
| 51 | 裝置代理 OS 整合 | N/A（StrawWU 獨有） | Phase6.11 有 code、rootfs 無 | DDP0–DDP3 |
| 52 | ISO 體積 / 開機時間預算 | 有 size gate | 6.1GB 無正式預算 | PERF0–PERF2 |

## Wave 對應

| Wave | 重點 |
|------|------|
| W0 | 12+ preflight + 基線 JSON |
| W1 | purge + Flathub + S1 |
| W2 | bug-reporter + calamares + registry + SEC/OBS |
| W3 | desktop meta + target-setup + W0 compat |
| W4 | shell + Hub + W1–W3 + L10N1 |
| W5 | firstboot + GRT + DDP skeleton |
| W6 | 全 E2E + HW1 實機 |
| W7 | RE 管線 + CI2 nightly |
| W8 | HW stable + initrd 深度 |

## HTML 交付

完整報告：`strawwu-distro-gap-analysis-v3-2026-07-04.html`（hermes-deliver）
