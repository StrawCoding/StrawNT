# Wave 1 — F1 strawwu-flatpak-setup

| 任務 ID | W1-F1-flathub |
|---------|---------------|
| 版本 | 1.0 |
| 日期 | 2026-07-04 |
| 狀態 | 待啟動 |

## 目標

建立 `strawwu-flatpak-setup` deb，於 chroot postinst 註冊 Flathub system remote；rootfs 具備 flatpak CLI。

## 範圍

### 必須交付

1. `os-image/debs/strawwu-flatpak-setup/` — debian/ + postinst
2. chroot 安裝 flatpak + 本 deb
3. 更新 `tests/preflight/test-flatpak.sh`（若需）使 PASS
4. Makefile target 整合（build-deb / install 到 rootfs）
5. `docs/plans/stage-reports/W1-F1-flathub-report.md`
6. VERSION bump

### 必讀

- `docs/plans/strawwu-flathub-plan.md`
- `docs/plans/strawwu-ai-worker-sop.md`

## PASS 條件

```bash
make test-flatpak
make preflight
# flatpak --version 在 rootfs 可用
# flathub remote 已註冊（system scope）
```

## 禁止

- 預裝大量 Flathub runtime（控制 ISO 體積）
- 預裝 gnome-software
- 改 kernel/
- worker 自宣稱 PASS

## 完成後

Hermes mark PASS → 自動啟動 W1-F2-nosnap。
