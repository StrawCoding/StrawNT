# W5-N4 finished-meta 階段報告

| 任務 | w5-n4-finished-meta |
|------|---------------------|
| 版本 | 0.4.1.25 |
| 日期 | 2026-07-05 |
| Worker | 階段 23/47（w5-n4-finished-meta） |
| 結果 | **待 Hermes mark** |

## 目標

Calamares finished 頁 zh_TW 翻譯 + `strawwu-install-init` target 依賴 meta：完成 install-init 四件套最後一塊 meta，並將 finished 完成頁文案接 L10N2 gettext。

## 交付物

| 類型 | 路徑 |
|------|------|
| install-init meta deb | `os-image/debs/strawwu-install-init/` |
| 生命週期 manifest | `usr/share/strawwu/install-init/install-init-manifest.yaml` |
| Calamares finished .ts/.qm | `strawwu-calamares-settings/usr/share/calamares/lang/calamares_zh_TW.{ts,qm}` |
| Branding slideshow l10n | `strawwu-install-init/usr/share/calamares/branding/strawwu/lang/calamares-strawwu_{en,zh_TW}.{ts,qm}` |
| finished.conf 註解 | `strawwu-calamares-settings/etc/calamares/modules/finished.conf` |
| target 合流 | `target-manifest.yaml` 新增 `strawwu-install-init` |
| chroot 建置 | `chroot-install-target-setup.sh` 納入 install-init deb |
| 單元測試 | `strawwu-install-init/tests/test-meta.py`、`strawwu-calamares-settings/tests/test-l10n-finished.py` |
| Preflight | `tests/preflight/test-finished-meta.sh` |
| baseline | `docs/plans/baselines/finished-meta-baseline.json` |
| Makefile | `test-finished-meta`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| strawwu-install-init | metapackage Depends initd + target-setup + firstboot |
| Calamares finished zh_TW | `calamares_zh_TW.qm` 覆寫 FinishedPage 成功/失敗/重開機字串（對齊 finished-copy.yaml） |
| Branding slideshow zh_TW | `calamares-strawwu_zh_TW.qm` 安裝進度字串（硬體偵測、分割區等） |
| Firstboot l10n | 維持 YAML（`firstboot.zh_TW.yaml`），manifest 文件化路徑 |
| Target staging | `target-manifest.yaml` 在 firstboot 與 desktop 之間插入 install-init |
| finished.conf | 維持 `user-checked` + `notifyOnFinished` + `systemctl -i reboot` |

## 變更檔案清單

```
VERSION (0.4.1.23 → 0.4.1.25)
Makefile
os-image/debs/strawwu-install-init/                         (新增)
os-image/debs/strawwu-calamares-settings/usr/share/calamares/lang/calamares_zh_TW.ts
os-image/debs/strawwu-calamares-settings/tests/test-l10n-finished.py
os-image/debs/strawwu-calamares-settings/build-deb.sh          (lrelease 編譯 .qm)
os-image/debs/strawwu-calamares-settings/etc/calamares/modules/finished.conf
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/scripts/chroot-install-target-setup.sh
tests/preflight/test-finished-meta.sh                         (新增)
tests/preflight/test-target-setup.sh                          (install-init 檢查)
docs/plans/baselines/finished-meta-baseline.json              (新增)
docs/plans/stage-reports/W5-N4-finished-meta-report.md        (本檔)
```

## 驗收命令輸出（2026-07-05 UTC-4）

### `make test-finished-meta` — exit 0（~0.5s）

Log: `/tmp/w5-n4-test-finished-meta.log`

```
=== W5-N4 finished-meta done: PASS ===
```

關鍵檢查：install-init meta Depends、target-manifest 合流、`calamares_zh_TW.qm` 打包、finished-copy 對齊、`strawwu-install-init_0.4.1.25_all.deb`（2.3K）、`calamares-settings` deb 含 `.ts`/`.qm`。

### `make preflight` — exit 0（~78s，2026-07-05T08:16 UTC-4）

Log: `/tmp/w5-n4-preflight.log`

含 W0–W4 全部階段 + W5-N3 firstboot + **W5-N4 finished-meta**（最終行 `=== W5-N4 finished-meta done: PASS ===`）。

WARN（預期）：squashfs/rootfs 尚未 chroot 安裝新版 `calamares-settings`（`calamares_zh_TW.qm` 待 chroot install）。

## 技術備註（治本）

1. **雙層 l10n 分離**：Calamares 核心 finished 字串走 `/usr/share/calamares/lang/calamares_zh_TW.qm`（calamares-settings）；branding slideshow 走 `/usr/share/calamares/branding/strawwu/lang/`（install-init），避免 dpkg 路徑衝突。
2. **canonical 文案鏈**：`finished-copy.yaml` → `calamares_zh_TW.ts` → `lrelease` → `.qm`；preflight 驗證「全部完成」等關鍵字一致。
3. **meta 不取代 staged debs**：target-manifest 仍逐包安裝；`strawwu-install-init` 作生命週期錨點與 Depends 合流。
4. **firstboot 不用 gettext**：維持 W5-N3 YAML i18n；manifest 僅文件化路徑供 L10N3 驗收追蹤。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| squashfs/rootfs calamares_zh_TW.qm | 需 `sudo bash os-image/scripts/chroot-install-calamares-settings.sh` |
| Calamares 全模組 zh_TW | L10N2 其餘模組（welcome/partition 等）待後續 Wave |
| install E2E finished 頁實機 | 待 **w6-n5-install-e2e** |
| Hub gettext | 待 W5+ Hub l10n |

## VERSION

`0.4.1.23` → `0.4.1.25`（iterate ×2）

## 建議 commit message

```
feat(w5): add install-init meta and Calamares finished zh_TW l10n

- strawwu-install-init metapackage (initd + target-setup + firstboot)
- calamares_zh_TW.qm for finished page; branding slideshow zh_TW in install-init
- target-manifest staging, test-finished-meta preflight + baseline
Tests: make test-finished-meta PASS, make preflight PASS
Version: 0.4.1.25
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T07:45:00-0400 | `[worker-START]` w5-n4-finished-meta |
| 2026-07-05T07:52:00-0400 | `[worker-DONE]` test-finished-meta + preflight exit 0 — 待 Hermes mark PASS |
| 2026-07-05T07:54:00-0400 | `[worker-VERIFY]` 複驗 test-finished-meta (~0.4s) + preflight (~119s) exit 0 |
| 2026-07-05T08:00:08-0400 | `[worker-TICK]` companion check status=IN_PROGRESS |
| 2026-07-05T08:00:30-0400 | `[worker-VERIFY]` 階段 23/47 複驗 test-finished-meta (~0.5s) + preflight (~45s) exit 0 — 待 Hermes mark PASS |
| 2026-07-05T08:15:08-0400 | `[worker-TICK]` companion check status=IN_PROGRESS |
| 2026-07-05T08:16:00-0400 | `[worker-VERIFY]` 階段 23/47 複驗 test-finished-meta (~0.5s) + preflight (~78s) exit 0 — 待 Hermes mark PASS |

## 下一階段

**w5-d4-context-menu**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-finished-meta
make preflight
```
