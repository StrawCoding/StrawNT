# Stage Report — official-release (Phase 8/8)

**版本目標**: 1.0.0.0（Q9）  
**當前 semver**: 1.0.0.0  
**階段**: 8/8 (official-release)  
**日期**: 2026-07-08  
**狀態**: IN_PROGRESS — `test-install-e2e` 重跑中（第 1 次於 bootloader 階段被 Terminated）  
**續跑狀態**: `docs/plans/official-release/RESUME.md`

---

## 解除阻塞

| # | 條件 | 狀態 | 說明 |
|---|------|------|------|
| 1–7 | Phase 0–6 PASS | ✅ | 前置階段全 PASS |
| 8 | Post-MVP 21/21 | ✅ | post-v09-engineering-closeout PASS |
| 9 | 使用者授權正式版 | ✅ | `.official-release-authorized`（2026-07-08） |

---

## Hermes 驗證命令

| 命令 | 結果 | 輸出摘要 |
|------|------|----------|
| `test -f .official-release-authorized` | ✅ | `authorized: 2026-07-08` / `target: 1.0.0.0` |
| `make build-iso` | ✅ | `BUILD_ISO_EXIT=0`；`StrawWU-1.0.0.0-amd64.iso`（4.8G） |
| `sha256sum -c SHA256SUMS` | ✅ | `os-image/output/StrawWU-1.0.0.0-amd64.iso: OK` |
| `make test-install-e2e` | ⏳ | 重跑中，log：`/tmp/test-install-e2e-1.0.0.0-rerun.log` |

### build-iso 證據

```
6e272f6d8ce9306c70a2712f87f0deb0c9fc6ffb48153540da03dc88e41ed691  StrawWU-1.0.0.0-amd64.iso
==> build complete (release-iso)
```

### preflight 證據

```
STRAWWU_OFFICIAL_RELEASE=1 STRAWWU_VERSION=1.0.0.0 make preflight
PREFLIGHT_EXIT=0
PASS: VERSION official release authorized: 1.0.0.0
```

---

## 本階段交付物

| 項目 | 路徑 |
|------|------|
| 授權標記 | `.official-release-authorized` |
| VERSION | `1.0.0.0` |
| ISO | `os-image/output/StrawWU-1.0.0.0-amd64.iso` |
| SHA256SUMS | 根目錄 + `os-image/output/SHA256SUMS` |
| DoD | `docs/plans/official-release/official-release-dod.md` |
| HTML hermes-deliver | `docs/plans/official-release/html/official-release-report.html` |
| validate | `tests/official-release/validate-official-release.py` |
| preflight 閘門 | `tests/preflight/test-official-release.sh` |
| 版本政策庫 | `tests/lib/version_policy.py` |
| 續跑狀態 | `docs/plans/official-release/RESUME.md` |

---

## 事件紀錄

1. 首次 E2E 跑約 93 分鐘至 `e2e-bootloader-setup`，shell 被 Terminated（無 `install-e2e-result.json`）。
2. 工作區曾出現 VERSION 回退至 `0.7.0.11`、`.official-release-authorized` 被刪除；已恢復。
3. 2026-07-08 17:14+08 以 nohup 重啟 `test-install-e2e`。

---

## 建議 Hermes

E2E exit 0 後執行：

```bash
sha256sum -c SHA256SUMS
STRAWWU_OFFICIAL_RELEASE=1 make test-official-release
```

再 mark `official-release`。**本報告不自行宣稱 PASS/FAIL。**
