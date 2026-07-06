# W6-R5 Deep Uninstall 階段報告

| 任務 | w6-r5-deep-uninstall |
|------|----------------------|
| 版本 | 0.4.1.37 |
| 日期 | 2026-07-05 |
| Worker | 階段 34/47（w6-r5-deep-uninstall） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Registry deep remove — 在標記 `install_state: removed` 之外，刪除 allowlist 內安裝路徑、可選 Flatpak 卸載，並於 scan 時同步已卸載的 Linux/Flatpak 條目。

## 交付物

| 類型 | 路徑 |
|------|------|
| deep remove 模組 | `components/strawwu-app-registry/src/deep_remove.rs` |
| Registry API | `deep_remove` · `deep_remove_by_desktop` · `sync_removed_from_scan` |
| CLI | `deep-remove` · `remove --deep` · `remove-by-desktop --deep` |
| Manifest | `os-image/debs/strawwu-desktop-actions/usr/share/strawwu/app-registry/deep-uninstall-manifest.yaml` |
| Preflight | `tests/preflight/test-deep-uninstall.sh` |
| Baseline | `docs/plans/baselines/deep-uninstall-baseline.json` |
| Hub 整合 | `app-registry-service.js` 預設 `deep-remove` + 回傳 shape 正規化 |
| 桌面整合 | `core.py` 右鍵移除改 `--deep` |
| Makefile | `test-deep-uninstall`；`preflight` 含 W6-R5 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 路徑 allowlist | `~/.strawwu`、`/opt/strawwu/apps`、使用者 desktop/flatpak/wine 前綴 |
| 系統路徑封鎖 | 禁止刪除 `/usr`、`/etc`、`/var/lib/strawwu` 等（對齊 security trust model） |
| dry-run | 預覽將刪路徑，不寫 registry、不碰磁碟 |
| Flatpak | `flatpak uninstall -y --system`（`STRAWWU_SKIP_FLATPAK_UNINSTALL` 可跳過） |
| scan 卸載同步 | `scan` 後對 Linux/Flatpak 掃描條目比對 registry，缺席者標記 removed |
| 保護條目 | `protected` / launcher / Win32 installer / seed 不參與 scan-remove |
| Hub / 桌面 | 移除操作預設 deep；API 仍暴露 `preview.id` 等欄位 |

## 驗收命令輸出（2026-07-05 22:12 UTC-4，worker 終驗）

### `make test-deep-uninstall` — exit 0（~0.6s）

Log: `/tmp/w6-r5-test-deep-uninstall.log`

```
=== W6-R5 deep-uninstall done: PASS ===
```

關鍵檢查：deep_remove 模組、CLI、scan sync、allow/forbidden manifest、cargo 32 unit tests、CLI deep-remove dry-run/commit、系統路徑 skip、scan 缺席 flatpak 標記 removed。

### `make preflight` — exit 0（~222s）

Log: `/tmp/w6-r5-preflight.log`

含 W0–W6-B5 全部階段 + **W6-R5 deep-uninstall** 全部 exit 0（無 FAIL）。終行：`=== W6-R5 deep-uninstall done: PASS ===`

## 變更檔案清單

```
VERSION (0.4.1.36 → 0.4.1.37)
Makefile
components/strawwu-app-registry/src/deep_remove.rs              (新增)
components/strawwu-app-registry/src/lib.rs
components/strawwu-app-registry/src/registry.rs
components/strawwu-app-registry/src/cli.rs
components/strawwu-app-registry/src/main.rs
components/strawwu-hub/src/main/app-registry-service.js
hub/src/main/app-registry-service.js
os-image/debs/strawwu-desktop-actions/usr/lib/strawwu-desktop-actions/core.py
os-image/debs/strawwu-desktop-actions/usr/share/strawwu/app-registry/deep-uninstall-manifest.yaml (新增)
tests/preflight/test-deep-uninstall.sh                          (新增)
docs/plans/baselines/deep-uninstall-baseline.json               (新增)
docs/plans/stage-reports/W6-R5-deep-uninstall-report.md         (本檔)
```

## 技術備註（治本）

1. **雙層移除語意保留**：`remove` 仍僅標記 registry（稽核）；`deep-remove` 在 allowlist 通過後清檔再標記，符合 W2-R1 預留的 W6-R5 hook 設計。
2. **APT Linux app 不硬刪 `/usr`**：系統套件路徑進 skip 清單；卸載由使用者透過 apt/flatpak 完成，scan sync 負責 registry 對齊。
3. **Win32 僅刪 prefix**：`~/.strawwu/apps/*` 等 allowlist 路徑；不觸 host 系統目錄。
4. **Hub 相容**：`normalizeRemoveResult` 將 `DeepRemoveResult.preview` 展平，Apps 分頁既有測試與 UI 不需改動。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| polkit admin prompt UI | CLI 層路徑封鎖；polkit 授權 UI 留待 SEC3 |
| APT purge 整合 | Linux 系統 app 僅 registry + scan sync，不自動 `apt remove` |
| chroot 重打包 | 新 manifest/CLI 需 dev-iso/release-iso 或 target 安裝同步 |
| Playwright E2E | 待 **w6-w6-wincompat-e2e** |

## VERSION

`0.4.1.36` → `0.4.1.37`（iterate）

## 建議 commit message

```
feat(w6): add registry deep uninstall with path allowlist and scan sync

- strawwu-app-registry deep-remove CLI; sync_removed_from_scan on scan
- Hub/desktop remove default to deep-remove; manifest + preflight baseline
Tests: make test-deep-uninstall PASS, make preflight PASS
Version: 0.4.1.37
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T21:58 UTC-4 | `[worker-START]` 階段 34/47 w6-r5-deep-uninstall |
| 2026-07-05T21:58 UTC-4 | `[worker-START]` companion supervisor |
| 2026-07-05T22:12 UTC-4 | `[worker-DONE]` 終驗：`make test-deep-uninstall` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w6-w6-wincompat-e2e**（Hermes mark PASS 後自動啟動，勿問使用者）。
