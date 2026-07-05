# W1-B1 Purge 階段報告

| 任務 | W1-B1-purge |
|------|-------------|
| 版本 | 0.4.1.1 |
| 日期 | 2026-07-04 |
| Worker | 階段 2/5（w1-b1-purge） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| Purge 腳本 | `os-image/scripts/chroot-purge-ubuntu-telemetry.sh` |
| Preflight 測試 | `tests/preflight/test-purge-baseline.sh` |
| Makefile targets | `test-purge-baseline`, `purge-ubuntu-telemetry` |
| 共用函式 | `tests/preflight/lib/common.sh`（`PURGE_TARGET_PACKAGES`、dpkg Status 解析） |
| 基線 JSON | `docs/plans/baselines/release-baseline.json`（purge 區塊、ubuntu-* 14） |
| Preflight 整合 | `make preflight` 含 `test-purge-baseline` |

## 驗收命令輸出（2026-07-04T15:42 UTC-4）

### `make test-purge-baseline` — exit 0

```
=== W1-B1 purge-baseline preflight ===
PASS: plan strawwu-ubuntu-components-plan.md
PASS: chroot-purge-ubuntu-telemetry.sh
PASS: W1-B1 kickoff
PASS: purge marker present (.../os-image/work/.purge-ubuntu-telemetry-ok)
PASS: rootfs absent apport / squashfs absent apport
PASS: rootfs absent apport-core-dump-handler / squashfs absent apport-core-dump-handler
PASS: rootfs absent whoopsie / squashfs absent whoopsie
PASS: rootfs absent ubuntu-report / squashfs absent ubuntu-report
PASS: rootfs absent ubuntu-pro-client / squashfs absent ubuntu-pro-client
PASS: rootfs absent ubuntu-pro-client-l10n / squashfs absent ubuntu-pro-client-l10n
PASS: rootfs absent ubuntu-advantage-desktop-daemon / squashfs absent ubuntu-advantage-desktop-daemon
PASS: rootfs absent snapd / squashfs absent snapd
PASS: rootfs absent snap-confine / squashfs absent snap-confine
PASS: retained ubuntu-keyring / calamares / ubuntu-minimal / ubuntu-desktop
PASS: squashfs ubuntu-* package count=14
=== W1-B1 purge-baseline done: PASS ===
```

Log: `/tmp/w1-b1-test-purge-baseline.log`

### `make preflight` — exit 0

含 `test-ubuntu-clone.sh`、`test-branding.sh`、`test-purge-baseline.sh` 全部 PASS。

Log: `/tmp/w1-b1-preflight.log`

### 附加驗證（同 session）

| 命令 | 結果 | Log |
|------|------|-----|
| `bash tests/preflight/test-release-baseline.sh` | PASS | `/tmp/w1-b1-release-baseline.log` |
| `bash tests/preflight/test-security-baseline.sh` | PASS | `/tmp/w1-b1-security-baseline.log` |
| `sudo bash os-image/scripts/chroot-purge-ubuntu-telemetry.sh` | idempotent skip（marker 存在） | `/tmp/w1-b1-purge-idempotent.log` |

## Purge 摘要

| 項目 | 狀態 |
|------|------|
| apport / whoopsie / ubuntu-report | 已自 rootfs/squashfs 移除 |
| ubuntu-pro-client / l10n / advantage-daemon | `dpkg --purge --force-depends` 移除 |
| snapd / snap 內容 | `dpkg --force-all` + `apt-mark hold` 阻擋回裝 |
| ubuntu-keyring / calamares | 保留 |
| ubuntu-minimal / ubuntu-desktop | 保留（desktop meta 以 force-depends 裝回） |
| squashfs ubuntu-* 計數 | 14（purge 前約 18） |
| rootfs `/snap` | 目錄不存在（snap 內容已清除） |

## 技術備註（治本）

1. **ubuntu-minimal Depends ubuntu-pro-client**：Noble 硬依賴；purge 使用 `dpkg --purge --force-depends`，後續 Wave 需 strawwu-minimal 等效 meta 取代。
2. **apport-gtk cascade**：`apt-mark manual` 保護 desktop meta；還原以 `dpkg -i --force-depends` 裝 ubuntu-desktop。
3. **snapd postrm**：chroot 內 `apt purge snapd` 易卡住；改 `dpkg --purge --force-all` 並預刪 `/var/lib/snapd`、`/snap`。
4. **dpkg Status 解析**：`common.sh` 改為 `/ ok installed/`，避免 `not-installed` 誤匹配。
5. **idempotent**：`.purge-ubuntu-telemetry-ok` marker；重跑需 `STRAWWU_FORCE=1`。

## 已知 WARN / 後續 Wave

- `ubuntu-minimal` 等仍有 **unmet Depends: ubuntu-pro-client**（預期，待 B 系列替換）。
- firefox/thunderbird snap 過渡包已移除；Flathub 瀏覽器由 **W1-F1** 承接。
- gnome-control-center 可能未完整配置（whoopsie-preferences 依賴）；不阻擋 B1 purge 驗證。

## 變更檔案

- `os-image/scripts/chroot-purge-ubuntu-telemetry.sh`（新增）
- `tests/preflight/test-purge-baseline.sh`（新增）
- `tests/preflight/lib/common.sh`
- `tests/preflight/test-security-baseline.sh`
- `tests/preflight/test-release-baseline.sh`
- `tests/preflight/test-ubuntu-clone.sh`
- `Makefile`
- `docs/plans/baselines/release-baseline.json`
- `VERSION`（0.4.1.1）

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-purge-baseline
make preflight
```

## 建議 commit message

```
feat(w1): purge Ubuntu telemetry/pro/snap from rootfs

- Add idempotent chroot-purge-ubuntu-telemetry.sh
- Add test-purge-baseline preflight + release-baseline purge block
Tests: make test-purge-baseline PASS; make preflight PASS
```

## 下一步

Hermes mark PASS → 自動啟動 **W1-F1-flathub**（依 kickoff 鎖序）。
