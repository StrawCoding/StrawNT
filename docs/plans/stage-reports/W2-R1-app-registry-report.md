# W2-R1 App Registry 階段報告

| 任務 | W2-R1-app-registry |
|------|---------------------|
| 版本 | 0.4.1.7 |
| 日期 | 2026-07-05 |
| Worker | 階段 8/47（w2-r1-app-registry） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| Rust crate | `components/strawwu-app-registry/` |
| CLI 二進位 | `strawwu-app-registry`（`cargo build` → `components/target/debug/`） |
| JSON Schema | `docs/plans/schemas/app-registry.schema.json` |
| 測試 fixture | `components/strawwu-app-registry/tests/fixtures/sample-registry.json` |
| Preflight 測試 | `tests/preflight/test-app-registry.sh` |
| Makefile | `test-app-registry`；`preflight` 含本階段 |
| Workspace | `components/Cargo.toml` 新增 `strawwu-app-registry` member |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 三表分離 | 使用者 App Registry（本 crate）· `strawwu-nt` AppDatabase stub（安裝/修復）· compat-db 留待 R6 |
| 儲存路徑 | `/var/lib/strawwu/app-registry.json`（`STRAWWU_APP_REGISTRY` 可覆寫） |
| 結構化日誌 | `/var/log/strawwu/app-registry.log`（best-effort append JSON lines） |
| Schema 版本 | `schema_version: "1.0"` 凍結 |
| CLI 命令 | `list` · `show` · `register` · `remove [--dry-run]` · `validate` · `version` |
| 安全邊界 | `protected: true` 拒絕 remove（exit 2）；dry-run 預覽不寫入 |
| bug-reporter 相容 | `apps[]` 含 `id`/`name`/`protected`，與 `bundle.py` 摘要邏輯對齊 |

## 驗收命令輸出（2026-07-05T02:58 UTC-4，worker 終驗）

### `make test-app-registry` — exit 0（~0.6s）

Log: `/tmp/w2-r1-test-app-registry.log`

```
=== W2-R1 app-registry done: PASS ===
```

關鍵檢查項（28 項）：crate 存在、schema 1.0 凍結、cargo build/test 9 項 unit test PASS、CLI register/list/show/remove/dry-run/validate、protected remove 拒絕（exit 2）、bug-reporter 摘要 shape OK。

### `make preflight` — exit 0（~22s）

Log: `/tmp/w2-r1-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + W2-B2 bug-reporter + W2-I1 calamares-settings + **W2-R1 app-registry** 全部 exit 0。

## 技術備註（治本）

1. **與 AppDatabase 分離**：`strawwu-nt::AppDatabase` 追蹤 Windows 安裝/修復狀態；本 registry 追蹤使用者可見 app 清單（Hub/桌面/移除），避免混表。
2. **移除語意**：`remove` 標記 `install_state: removed` 而非硬刪紀錄，保留稽核與 deep-uninstall 後續 hook 空間（W6-R5）。
3. **Phase 6 預設**：`execution_backend` 預設 `native`（共享 SubsystemSession）；`container`/`microvm` 僅覆寫。
4. **無 legacy 複製**：v3.0 cleanroom 全新實作；僅對齊 OBS/安全模型路徑約定。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| OS 映像 deb 安裝 | 未打包 deb（本階段 crate+CLI）；W4/W5 整合 Hub/桌面/context menu |
| polkit 授權 | CLI 層 protected 檢查；polkit policy 留待 W2-trust-baseline |
| compat-db seed hook | R6（golden-apps → registry seed） |
| Hub Apps 分頁 UI | W4-R2 |
| 桌面右鍵移除 | W5-D4 |
| install hooks | W5-R4 |
| deep uninstall | W6-R5 |

## VERSION

`0.4.1.6` → `0.4.1.7`（iterate）

## 建議 commit message

```
feat(w2): add strawwu-app-registry crate, CLI, and schema

- User app registry at /var/lib/strawwu/app-registry.json (schema 1.0)
- CLI: list/show/register/remove/validate with protected-app guard
- JSON schema frozen; preflight test-app-registry + Makefile integration
Tests: make test-app-registry PASS, make preflight PASS
Version: 0.4.1.7
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T02:42:49-0400 | `[worker-START]` companion supervisor started |
| 2026-07-05T02:57:49-0400 | `[worker-TICK]` periodic companion check status=IN_PROGRESS |
| 2026-07-05T02:58:00-0400 | `[worker-DONE]` 終驗完成：`make test-app-registry` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w2-n1-initd**（Hermes mark PASS 後自動啟動，依 kickoff 鎖序）。
