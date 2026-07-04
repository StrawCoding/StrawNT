# StrawWU 安裝初始化工具計畫

| 代號 | N0–N5 | Wave | W0–W6 |

## 四件套 deb

`strawwu-initd` · `strawwu-install-init` · `strawwu-target-setup` · `strawwu-firstboot`

## 生命週期

Calamares → target-setup(chroot) → reboot → boot-selfcheck → login → firstboot → desktop

## state

`/var/lib/strawwu/setup/state.json`（schema versioned，合 UPG）

## 現況 ~10%

## 完整規格

Hermes: `strawwu-install-init-tools-plan-2026-07-04.html`
