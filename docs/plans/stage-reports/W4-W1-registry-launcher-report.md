# W4-W1 Registry ↔ Launcher 階段報告

| 任務 | w4-w1-registry-launcher |
|------|-------------------------|
| 版本 | 0.4.1.20 |
| 日期 | 2026-07-05 |
| Worker | 階段 20/47（w4-w1-registry-launcher） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 修復紀錄（2026-07-05T06:50 UTC-4）

並行 `cargo test` 時 `STRAWWU_APP_REGISTRY` 環境變數競態，導致 `register_launch_writes_registry` 間歇 FAIL。於 `registry.rs` 測試模組加入 `RegistryEnvGuard`（mutex + restore on drop）隔離 env，治本修復。

## 目標

Windows app 註冊整合 — `strawwu run` / `install` 寫入 User App Registry，`apps list` / `status` 讀取登錄表（Wave W1 DoD）。

## 交付物

| 類型 | 路徑 |
|------|------|
| Launcher 整合模組 | `components/strawwu-launcher/src/registry.rs` |
| Launcher CLI | `components/strawwu-launcher/src/main.rs` — run/install/apps/status 整合 |
| Registry upsert API | `components/strawwu-app-registry/src/registry.rs` — `upsert_from_launch` / `upsert_from_install` |
| baseline 元資料 | `os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml` |
| Preflight 測試 | `tests/preflight/test-wincompat-registry.sh` |
| baseline JSON | `docs/plans/baselines/wincompat-registry-baseline.json` |
| Makefile | `test-wincompat-registry`；`preflight` 含本階段 |

## 功能摘要

| 項目 | 實作 |
|------|------|
| `strawwu run` | 啟動前 `upsert_from_launch` — kind=win32/linux、source=launcher、install_path=binary 父目錄 |
| 重複執行 | upsert 更新 name/path/backend，不 Duplicate 失敗 |
| `strawwu install` | stub 仍記錄 `install_state=pending`、source=installer |
| `strawwu apps list` | 讀 User App Registry，輸出 `id\tname\tkind` |
| `strawwu status` | 顯示已登錄 app 數量 |
| app_id 推導 | binary stem → slug（schema `^[a-z0-9][a-z0-9._-]{0,63}$`） |
| 環境覆寫 | `STRAWWU_APP_REGISTRY` / `STRAWWU_APP_REGISTRY_LOG` |
| Phase 6 預設 | execution_backend 預設 native；container/microvm 僅覆寫 |
| 三表分離 | 僅 User App Registry；不混 compat-db / AppDatabase |

## 驗收命令輸出（2026-07-05T06:52 UTC-4，worker 終驗）

### `make test-wincompat-registry` — exit 0（~1.4s）

Log: `/tmp/w4-w1-test-wincompat-registry.log`

```
=== W4-W1 wincompat-registry done: PASS ===
```

關鍵檢查項：launcher registry.rs、RegistryStore upsert、cargo build/test launcher（34 unit tests）+ app-registry（10 unit tests）、`strawwu run` 寫入 demo-app（win32/launcher/installed）、`apps list`、`--backend container` upsert、`install` pending、status 計數 2。

### `make preflight` — exit 0（~111s）

Log: `/tmp/w4-w1-preflight.log`

含 W0 baseline + W1–W3 全部階段 + W4-D2/D3/R2/F3 + **W4-W1 wincompat-registry** 全部 exit 0（最終行 `=== W4-W1 wincompat-registry done: PASS ===`）。

## 變更檔案清單

```
VERSION (0.4.1.19 → 0.4.1.20)
Makefile
components/strawwu-launcher/Cargo.toml
components/strawwu-launcher/src/lib.rs
components/strawwu-launcher/src/main.rs
components/strawwu-launcher/src/registry.rs          (新增；含 RegistryEnvGuard 測試隔離)
components/strawwu-app-registry/src/registry.rs
os-image/debs/strawwu-wincompat/usr/share/strawwu/wincompat/baseline.yaml
tests/preflight/test-wincompat-registry.sh           (新增)
docs/plans/baselines/wincompat-registry-baseline.json (新增)
docs/plans/stage-reports/W4-W1-registry-launcher-report.md (本檔)
```

## 技術備註（治本）

1. **庫整合而非 shell out**：launcher 直接 link `strawwu-app-registry` crate，Hub 移除仍走 CLI；讀寫語意一致。
2. **upsert 語意**：重跑同一 exe 更新 path/backend，removed app 可被 run 重新激活為 installed。
3. **install stub 仍登錄**：pending 狀態供 Hub Apps 分頁預覽與 W5 install hooks 銜接。
4. **無 legacy 複製**：v3.0 cleanroom；對齊 W2-R1 schema 1.0 與 security trust model protected 邊界。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| 完整 install 流程（prefix/VFS） | 待 **w5-r4** / Windows compat W2 |
| 桌面 icon / context menu | 待 **w5-d4** |
| Hub 即時刷新（run 後） | Hub 讀檔；需手動 refresh 或後續 IPC |
| wincompat deb 重打包 | chroot 變更需 `make dev-iso`/`release-iso` 才進 ISO |
| Playwright E2E | 待 **w6-w6-wincompat-e2e** |
| deep uninstall | 待 **w6-r5** |

## VERSION

`0.4.1.19` → `0.4.1.20`（iterate）

## 建議 commit message

```
feat(w4): integrate strawwu-launcher with app registry

- strawwu run upserts AppRecord; install records pending; apps list/status read registry
- RegistryStore upsert_from_launch/install; preflight test-wincompat-registry
Tests: make test-wincompat-registry PASS, make preflight PASS
Version: 0.4.1.20
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T06:42 UTC-4 | `[worker-START]` w4-w1-registry-launcher |
| 2026-07-05T06:50 UTC-4 | 修復 registry 測試 env 競態（RegistryEnvGuard） |
| 2026-07-05T06:52 UTC-4 | `[worker-DONE]` 終驗：`make test-wincompat-registry` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w4-l10n-ime**（Hermes mark PASS 後自動啟動，勿問使用者）。
