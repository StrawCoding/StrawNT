# Wave 1 — B1 Purge Ubuntu 遙測/Pro/Snap

| 任務 ID | W1-B1-purge |
|---------|-------------|
| 版本 | 1.0 |
| 日期 | 2026-07-04 |
| 狀態 | 實作完成，待 Hermes mark |

## 目標

自 rootfs（`os-image/work/rootfs`）purge Ubuntu 遙測、Pro、Snap 相關套件，並建立可重複的 chroot 腳本與 preflight 驗證。

## 範圍

### 必須 purge（rootfs chroot）

- `apport` / `apport-core-dump-handler`（若存在）
- `whoopsie`
- `ubuntu-report`
- `ubuntu-pro-client` / `ubuntu-pro-client-l10n`
- `ubuntu-advantage-desktop-daemon`（若存在）
- `snapd` / `snap-confine` / `ubuntu-core*` snap 相關

### 必須交付

1. `os-image/scripts/chroot-purge-ubuntu-telemetry.sh` — idempotent chroot purge
2. `tests/preflight/test-purge-baseline.sh` — 驗證上述套件不在 squashfs/rootfs
3. Makefile target `test-purge-baseline`（及可選 `purge-ubuntu-telemetry`）
4. 更新 `docs/plans/baselines/release-baseline.json`（ubuntu 套件計數、purge 狀態）
5. `docs/plans/stage-reports/W1-B1-purge-report.md`
6. VERSION bump（`scripts/bump-version.sh`）

### 必讀

- `docs/plans/strawwu-ubuntu-components-plan.md`
- `docs/plans/strawwu-security-trust-model.md`
- `docs/plans/strawwu-ai-worker-sop.md`

## PASS 條件

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
sudo bash os-image/scripts/chroot-purge-ubuntu-telemetry.sh
make test-purge-baseline
make preflight
# exit 0
```

squashfs（`os-image/work/squashfs-root`）或 rootfs 中上述 telemetry 套件均不存在。

## 禁止

- 修改 `kernel/` 源碼
- purge `ubuntu-keyring` / casper 相容套件
- `SKIP_SQUASHFS=1` 並行 boot-test
- worker 自宣稱 PASS

## 證據路徑

- purge 腳本：`os-image/scripts/chroot-purge-ubuntu-telemetry.sh`
- preflight：`tests/preflight/test-purge-baseline.sh`
- 階段報告：`docs/plans/stage-reports/W1-B1-purge-report.md`

## 完成後

Hermes mark PASS → 自動啟動 W1-F1-flathub（勿問使用者）。
