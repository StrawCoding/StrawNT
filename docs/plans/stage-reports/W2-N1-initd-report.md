# W2-N1 Initd 階段報告

| 任務 | W2-N1-initd |
|------|-------------|
| 版本 | 0.4.1.8 |
| 日期 | 2026-07-05 |
| Worker | 階段 9/47（w2-n1-initd） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 交付物

| 類型 | 路徑 |
|------|------|
| deb 套件 | `os-image/debs/strawwu-initd/debian/` |
| CLI | `os-image/debs/strawwu-initd/usr/bin/strawwu-initd` |
| 核心邏輯 | `os-image/debs/strawwu-initd/usr/lib/strawwu-initd/state.py` |
| JSON Schema | `docs/plans/schemas/setup-state.schema.json` |
| 單元測試 | `os-image/debs/strawwu-initd/tests/test-state.py` |
| deb 建置 | `os-image/debs/strawwu-initd/build-deb.sh` |
| Preflight 測試 | `tests/preflight/test-init-tools.sh`（W2-N1 強化） |
| Makefile | `test-init-tools`；`preflight` 含 init-tools |

## 功能摘要

| 項目 | 實作 |
|------|------|
| 共用 state | `/var/lib/strawwu/setup/state.json`（`STRAWWU_SETUP_STATE` 可覆寫） |
| Schema 版本 | `schema_version: "1.0"` 凍結（合 UPG0 migrator 預留） |
| 生命週期欄位 | `install` · `target_setup` · `boot_selfcheck` · `firstboot` |
| CLI 命令 | `init` · `show` · `get` · `set` · `validate` · `repair` · `migrate` · `version` |
| 結構化日誌 | `/var/log/strawwu/initd.log`（best-effort JSON lines） |
| repair | 備份損毀 state → 重新初始化（對齊 upgrade-recovery rescue 流程） |
| 環境變數 | `STRAWWU_SETUP_STATE` · `STRAWWU_INITD_LOG` |

## 驗收命令輸出（2026-07-05T03:28 UTC-4，companion 終驗）

### `make test-init-tools` — exit 0（~1.1s）

Log: `/tmp/w2-n1-test-init-tools.log`

```
=== W2-N1 init-tools done: PASS ===
```

關鍵檢查項：deb scaffold initd 存在、schema 1.0 凍結、6 項 unit test PASS、deb 建置 `strawwu-initd_0.4.1.8_all.deb`（9.6K）、CLI init/get/set/validate/repair/migrate、無效 lifecycle 拒絕、lifecycle shape OK。

### `make preflight` — exit 0（~28s）

Log: `/tmp/w2-n1-preflight.log`

含 W0 baseline + W1-B1 purge + W1-F1 flatpak + W1-F2 nosnap + W1-S1 initrd + **W2-N1 init-tools** + W2-B2 bug-reporter + W2-I1 calamares-settings + W2-R1 app-registry 全部 exit 0。

## 技術備註（治本）

1. **四件套之首**：`strawwu-initd` 提供共用 state.json CLI；`install-init` / `target-setup` / `firstboot` 留待 W3-N2 / W5-N3 等後續 Wave 呼叫本 CLI。
2. **Schema 版本化**：`migrate` 目前對 1.0 noop；非 1.0 版本 raise，為 UPG0 migrator 預留明確邊界。
3. **repair 語意**：驗證失敗或 JSON 損毀時備份 `.bak.<ts>` 後 force re-init，對齊 `strawwu-upgrade-recovery-plan.md` rescue 流程。
4. **無 legacy 複製**：v3.0 cleanroom 全新 Python 實作；僅對齊 install-init / upgrade 計畫路徑約定。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| chroot / ISO 安裝 | 未打包進 rootfs（本階段 deb+CLI）；W3+ 整合 target-setup |
| `strawwu-install-init` deb | 待 W3+ |
| `strawwu-target-setup` deb | 待 W3-N2 |
| `strawwu-firstboot` deb | 待 W5-N3 |
| firstboot 六步精靈寫入 state | W5-N3 呼叫 `strawwu-initd set` |
| UPG0 schema migrator | 待 upgrade Wave |
| OBS4 結構化 JSON log 全面接線 | 本階段 initd.log 已就緒 |

## VERSION

`0.4.1.7` → `0.4.1.8`（iterate）

## 建議 commit message

```
feat(w2): add strawwu-initd shared setup state.json CLI

- Schema 1.0 at /var/lib/strawwu/setup/state.json
- CLI: init/show/get/set/validate/repair/migrate
- Unit tests + test-init-tools preflight + Makefile target
Tests: make test-init-tools PASS, make preflight PASS
Version: 0.4.1.8
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T03:16:30-0400 | `[worker-DONE]` stage ended — 待 Hermes mark PASS |
| 2026-07-05T03:28:38-0400 | commit `f8009578f` feat(w2): strawwu-initd |
| 2026-07-05T03:28:50-0400 | `[worker-TICK]` companion 重跑 test-init-tools + preflight — exit 0 |

## 下一步

**w2-trust-baseline**（Hermes mark PASS 後自動啟動，依 kickoff 鎖序）。
