# W5-D4 桌面右鍵移除階段報告

| 任務 | w5-d4-context-menu |
|------|-------------------|
| 版本 | 0.4.1.26 |
| 日期 | 2026-07-05 |
| Worker | 階段 24/47（w5-d4-context-menu） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

desktop Actions + favorites 同步 — Nautilus 右鍵「從 StrawWU 移除」、`.desktop` Desktop Action 注入、GNOME favorites 同步；與 Hub Apps 分頁共用 `strawwu-app-registry` 移除語意。

## 交付物

| 類型 | 路徑 |
|------|------|
| desktop-actions deb | `os-image/debs/strawwu-desktop-actions/` |
| 移除 CLI | `usr/bin/strawwu-desktop-remove` |
| Nautilus 腳本 | `usr/share/nautilus/scripts/Remove from StrawWU` |
| Python 核心 | `usr/lib/strawwu-desktop-actions/{core,desktop_parse,favorites,i18n}.py` |
| manifest | `usr/share/strawwu/desktop-actions/desktop-actions-manifest.yaml` |
| i18n | `locale/desktop-actions.{en,zh_TW}.yaml` |
| Registry desktop API | `components/strawwu-app-registry/src/desktop.rs` |
| Registry CLI | `remove-by-desktop`、`register --desktop-entry` |
| OS 打包 CLI | deb 內建 `/usr/bin/strawwu-app-registry`（release build） |
| Desktop 整合 | `strawwu-desktop` Depends `strawwu-desktop-actions` |
| Target 合流 | `target-manifest.yaml` 在 desktop 前插入 desktop-actions |
| chroot 建置 | `chroot-install-target-setup.sh` build/stage 納入 desktop-actions |
| Preflight | `tests/preflight/test-context-menu.sh` |
| baseline | `docs/plans/baselines/context-menu-baseline.json` |
| Makefile | `test-context-menu`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 右鍵移除 | Nautilus script → `strawwu-desktop-remove --desktop <path>` |
| Desktop Action | `RemoveFromStrawWU` 注入 `.desktop`（`X-StrawWU-App-Id` + Exec） |
| Registry 解析 | `remove-by-desktop` 依 `desktop_entry` / basename / `X-StrawWU-App-Id` slug |
| favorites 同步 | 移除後自 `org.gnome.shell favorite-apps` 刪除對應 `.desktop` id |
| protected 邊界 | registry `Protected` → exit 2；CLI 顯示 zh_TW/en 錯誤 |
| Hub 對齊 | 同一 registry JSON + 相同 removed 語意（Hub 仍走 CLI `remove`） |
| 三表分離 | 僅 User App Registry；不混 compat-db / AppDatabase |

## 變更檔案清單

```
VERSION (0.4.1.25 → 0.4.1.26)
Makefile
components/strawwu-app-registry/src/{lib,registry,cli,main,desktop}.rs
os-image/debs/strawwu-desktop-actions/                         (新增)
os-image/debs/strawwu-desktop/debian/control
os-image/debs/strawwu-desktop/tests/test-meta.py
os-image/debs/strawwu-target-setup/usr/share/strawwu/target-setup/target-manifest.yaml
os-image/scripts/chroot-install-target-setup.sh
tests/preflight/test-context-menu.sh                           (新增)
docs/plans/baselines/context-menu-baseline.json                (新增)
docs/plans/stage-reports/W5-D4-context-menu-report.md          (本檔)
```

## 驗收命令輸出（2026-07-05 UTC-4）

### `make test-context-menu` — exit 0（~3.9s，2026-07-05T08:36 UTC-4 複驗）

Log: `/tmp/w5-d4-test-context-menu.log`

```
=== W5-D4 context-menu done: PASS ===
```

關鍵檢查：desktop-actions deb 建置、`remove-by-desktop` dry-run、Desktop Action 注入、Nautilus script、`strawwu-desktop-remove` 整合、7 Python unit tests、15 Rust unit tests。

### `make preflight` — exit 0（~141s，2026-07-05T08:38 UTC-4 複驗）

Log: `/tmp/w5-d4-preflight.log`

含 W0–W4 全部階段 + W5-N3/N4 + **W5-D4 context-menu**（最終行 `=== W5-D4 context-menu done: PASS ===`）。

WARN（預期）：squashfs/rootfs `calamares_zh_TW.qm` 待 chroot install（延續 W5-N4）。

## 技術備註（治本）

1. **移除雙路徑收斂**：Hub Apps 分頁與桌面右鍵皆委派 `strawwu-app-registry` 標記 `install_state=removed`；桌面路徑額外 sync favorites。
2. **Desktop Action 而非 legacy Nautilus 擴充**：`.desktop` `[Desktop Action RemoveFromStrawWU]` 可於 icon 右鍵直接觸發；Nautilus script 覆蓋檔案管理器選取。
3. **首次 OS 打包 app-registry CLI**：隨 desktop-actions deb 安裝至 `/usr/bin/strawwu-app-registry`，對齊 wincompat 打包 strawwu 的模式。
4. **favorites 最佳努力**：無 GNOME session 時 `STRAWWU_SKIP_FAVORITES_SYNC=1` 或 gsettings 不可寫則略過，不阻斷 registry 移除。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| install hooks / 檔案刪除 | 待 **w5-r4** / **w6-r5** deep-uninstall |
| launcher 自動注入 Desktop Action | 待 **w5-w4** wincompat-gui |
| Hub 移除後 favorites 即時刷新 | Hub 未呼叫 favorites sync；桌面路徑已 sync |
| Playwright 桌面右鍵 E2E | 待 ISO/live 環境 |
| polkit 授權 UI | CLI protected 邊界；桌面顯示錯誤訊息 |

## VERSION

`0.4.1.25` → `0.4.1.26`（iterate）

## 建議 commit message

```
feat(w5): add desktop context menu remove and favorites sync

- strawwu-desktop-actions deb: Nautilus script, Desktop Action inject, favorites gsettings sync
- app-registry remove-by-desktop + register --desktop-entry; ship CLI in target deb
Tests: make test-context-menu PASS, make preflight PASS
Version: 0.4.1.26
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T08:20 UTC-4 | `[worker-START]` w5-d4-context-menu |
| 2026-07-05T08:26 UTC-4 | `[worker-DONE]` 初版實作 + test-context-menu + preflight exit 0 |
| 2026-07-05T08:27 UTC-4 | `[worker-TICK]` Hermes tick175 啟動 w5-d4（w5-n4 PASS） |
| 2026-07-05T08:29 UTC-4 | `[worker-DONE]` 複驗 test-context-menu + preflight exit 0 — 待 Hermes mark PASS |
| 2026-07-05T08:35 UTC-4 | `[worker-TICK]` Hermes periodic companion check status=IN_PROGRESS |
| 2026-07-05T08:36 UTC-4 | `[worker-DONE]` tick 複驗 test-context-menu exit 0 |
| 2026-07-05T08:38 UTC-4 | `[worker-DONE]` tick 複驗 preflight exit 0 — 待 Hermes mark PASS |

## 下一步

**w5-r4-install-hooks**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-context-menu
make preflight
```
