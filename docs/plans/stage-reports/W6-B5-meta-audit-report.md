# W6-B5 Meta Audit 階段報告

| 任務 | w6-b5-meta-audit |
|------|------------------|
| 版本 | 0.4.1.36 |
| 日期 | 2026-07-05 |
| Worker | 階段 33/47（w6-b5-meta-audit） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

ubuntu-* 清零審計：定義允許清單、以 `strawwu-minimal` 取代 `ubuntu-minimal`（無 `ubuntu-pro-client` 依賴），並以 preflight 掃描 rootfs/squashfs 禁止上游 meta 殘留。

## 交付物

| 類型 | 路徑 |
|------|------|
| minimal meta deb | `os-image/debs/strawwu-minimal/` |
| 審計 manifest | `usr/share/strawwu/meta-audit/meta-audit-manifest.yaml` |
| 單元測試 | `os-image/debs/strawwu-minimal/tests/test-meta.py` |
| Preflight | `tests/preflight/test-meta-audit.sh` |
| baseline | `docs/plans/baselines/meta-audit-baseline.json` |
| Makefile | `test-meta-audit`；`preflight` 含 W6-B5 |
| target 合流 | `target-manifest.yaml` 新增 `strawwu-minimal` |
| chroot 整合 | `chroot-install-target-setup.sh` 安裝 minimal + purge `ubuntu-minimal`/`ubuntu-standard` |
| 關聯更新 | `test-purge-baseline.sh`、`test-desktop-stack.sh` baseline |

## 功能摘要

| 項目 | 實作 |
|------|------|
| strawwu-minimal | 對齊 Noble `ubuntu-minimal` 核心 Depends，排除 `ubuntu-pro-client`；Conflicts `ubuntu-minimal` |
| 禁止 upstream metas | `ubuntu-minimal`、`ubuntu-desktop`、`ubuntu-desktop-minimal`、`ubuntu-session`、`ubuntu-standard` |
| 允許 compat 套件 | `ubuntu-keyring`、`ubuntu-drivers-common`、`ubuntu-release-upgrader-*`、`ubuntu-settings`、`ubuntu-mono`、`ubuntu-wallpapers*`、`ubuntu-docs` |
| 必要 StrawWU metas | `strawwu-minimal` + `strawwu-desktop` |
| chroot 步驟 | disable-upstream-init 後安裝 `strawwu-minimal`，purge 上游 base metas |
| 檔案系統審計 | 對比 manifest allowlist；禁止項以 WARN 提示 chroot 重跑（與 W5-B4 過渡策略一致） |

## 變更檔案清單

```
os-image/debs/strawwu-minimal/                         (新增)
tests/preflight/test-meta-audit.sh                     (新增)
docs/plans/baselines/meta-audit-baseline.json          (新增)
docs/plans/stage-reports/W6-B5-meta-audit-report.md    (本檔)
os-image/debs/strawwu-target-setup/.../target-manifest.yaml
os-image/scripts/chroot-install-target-setup.sh
tests/preflight/test-purge-baseline.sh
tests/preflight/test-desktop-stack.sh
os-image/debs/strawwu-desktop/usr/share/doc/strawwu-desktop/README
Makefile
VERSION (0.4.1.35 → 0.4.1.36)
docs/plans/baselines/desktop-baseline.json             (preflight 更新)
```

## 驗收命令輸出（2026-07-05 21:57 UTC-4，worker 階段 33 Hermes TICK 複驗）

### `make test-meta-audit` — exit 0（~0.8s）

Log: `/tmp/w6-b5-test-meta-audit.log`

```
=== W6-B5 meta-audit done: PASS ===
```

關鍵檢查項：manifest schema v1、5 項單元測試 PASS、`strawwu-minimal_0.4.1.36_amd64.deb`（1.9K）、target-manifest 含 strawwu-minimal。rootfs/squashfs 仍有 4 個禁止 upstream meta（WARN，待 chroot 重跑）；allowlist 內 8 個 compat 套件 count=12。

### `make preflight` — exit 0（~103s）

Log: `/tmp/w6-b5-preflight.log`

含 W0–W6-F5 全部階段 + **W6-B5 meta-audit** 全部 exit 0（34 個子階段 PASS，無 FAIL）。

## 技術備註（治本）

1. **治本取代 ubuntu-pro-client 依賴**：Noble `ubuntu-minimal` 硬依賴 `ubuntu-pro-client`；`strawwu-minimal` 以相同 CLI base Depends 但不引入 Pro/telemetry，並 Conflicts 上游 meta 防止 apt 回拉。
2. **allowlist 而非盲目 purge**：`ubuntu-keyring`、drivers、release-upgrader 等內部相容套件保留至後續替換 wave；審計腳本只 fail 源碼/manifest/deb 層，檔案系統層以 WARN 引導 chroot 同步。
3. **與 W5-B4 銜接**：upstream desktop metas 仍由 `strawwu-disable-upstream-init` purge；W6-B5 補上 base meta（minimal/standard）與審計 baseline。
4. **Calamares 路徑已就緒**：新安裝 target 經 target-manifest 會裝入 `strawwu-minimal`；live ISO rootfs 需 `sudo bash os-image/scripts/chroot-install-target-setup.sh` 同步。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| rootfs/squashfs chroot 同步 | 待 `sudo bash os-image/scripts/chroot-install-target-setup.sh` |
| ubuntu-drivers-common 替換 | 待後續 B 系列 / upgrade wave |
| ubuntu-release-upgrader 替換 | 待 strawwu-upgrade |
| ubuntu-docs 替換 | 待 w6-doc1 / w8-doc-handbook |
| deep uninstall 驗證 | 待 w6-r5-deep-uninstall |

## VERSION

`0.4.1.35` → `0.4.1.36`（iterate）

## 建議 commit message

```
feat(w6): add ubuntu-* meta audit and strawwu-minimal meta

- strawwu-minimal replaces ubuntu-minimal without ubuntu-pro-client
- meta-audit-manifest allowlist + test-meta-audit preflight + baseline
- chroot-install-target-setup installs minimal and purges upstream base metas
Tests: make test-meta-audit PASS, make preflight PASS
Version: 0.4.1.36
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05T21:38 UTC-4 | worker 初版驗收 test-meta-audit + preflight exit 0 |
| 2026-07-05T21:41 UTC-4 | `[worker-DONE]` 複驗 test-meta-audit + preflight exit 0 |
| 2026-07-05T21:46 UTC-4 | `[worker-DONE]` Hermes TICK 複驗 test-meta-audit + preflight exit 0 |
| 2026-07-05T21:54 UTC-4 | Hermes `[worker-TICK]` periodic companion check status=IN_PROGRESS |
| 2026-07-05T21:57 UTC-4 | `[worker-DONE]` Hermes TICK 複驗 test-meta-audit + preflight exit 0 — 待 Hermes mark PASS |

## 下一階段

**w6-r5-deep-uninstall**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-meta-audit
make preflight
```
