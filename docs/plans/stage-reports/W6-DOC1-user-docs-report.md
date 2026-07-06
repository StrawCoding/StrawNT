# W6-DOC1 使用者文件階段報告

| 任務 | w6-doc1-user-docs |
|------|-------------------|
| 版本 | 0.4.1.40 |
| 日期 | 2026-07-05 |
| Worker | 階段 37/47（w6-doc1-user-docs） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

建立 `docs/user/` 安裝／Live／firstboot／救援使用者文件（DOC0 索引 + DOC1 指南），含 HTML hermes-deliver 產物與 preflight gate。

## 交付物

| 類型 | 路徑 |
|------|------|
| 文件索引（DOC0） | `docs/user/README.md` |
| 安裝指南 | `docs/user/install-guide.md` |
| 救援指南 | `docs/user/rescue-guide.md` |
| 機器可讀清單 | `docs/user/manifest.json` |
| HTML（hermes-deliver） | `docs/user/html/install-guide.html`、`docs/user/html/rescue-guide.html` |
| HTML 渲染器 | `tests/user-docs/render-html.py` |
| 驗證腳本 | `tests/user-docs/validate-user-docs.py` |
| Preflight gate | `tests/preflight/test-user-docs.sh` |
| baseline JSON | `docs/plans/baselines/user-docs-baseline.json` |
| Makefile | `test-user-docs`；`preflight` 含本階段 |

## 功能摘要

| 元件 | 說明 |
|------|------|
| **install-guide** | Live USB（Rufus/dd/Ventoy）、Calamares 安裝、firstboot 六步精靈、bug-reporter |
| **rescue-guide** | Live chroot、`strawwu-initd repair`、`strawwu-target-setup --repair-only`、GRUB 修復、smoke-live 實機流程 |
| **誠實邊界** | `strawwu-upgrade --rollback`、專用 Rescue GRUB 項目標記為 UPG 延後；社群支援 URL **TBD**（deferred scope §4） |
| **render-html.py** | Markdown → 自含式深色 Teal 主題 HTML（對齊 SOP hermes-deliver 風格） |
| **validate-user-docs.py** | 結構、關鍵字、manifest schema、HTML 產物 gate |

### 文件化 W6-HW1 後續項

- `smoke-live.sh` 實機合併流程已寫入 install-guide §2.4 與 rescue-guide §7。

## 驗收命令輸出

### 終驗（2026-07-05 23:22 UTC-4，companion worker TICK 重驗）

#### `make test-user-docs` — exit 0

Log: `/tmp/w6-doc1-test-user-docs.log`

```
PASS: rendered docs/user/html/install-guide.html
PASS: rendered docs/user/html/rescue-guide.html
=== W6-DOC1 user-docs validation ===
（全 31 項 PASS，含 manifest schema、HTML Teal #14b8a6、VERSION 0.4.1.40）
=== W6-DOC1 user-docs done: PASS ===
```

#### `make preflight` — exit 0（~222s）

Log: `/tmp/w6-doc1-preflight.log`

含 W0–W6-HW1 全部階段 + **W6-DOC1 user-docs** 終行：`=== W6-DOC1 user-docs done: PASS ===`

### 初驗（2026-07-05 23:09 UTC-4）

同上結果；本 companion session 於 Hermes `[worker-TICK]` 後重跑確認無回歸。

## 變更檔案清單

```
VERSION (0.4.1.39 → 0.4.1.40)
Makefile
docs/user/README.md                                          (新增)
docs/user/install-guide.md                                   (新增)
docs/user/rescue-guide.md                                    (新增)
docs/user/manifest.json                                      (新增)
docs/user/html/install-guide.html                            (新增，render 產物)
docs/user/html/rescue-guide.html                             (新增，render 產物)
tests/user-docs/render-html.py                               (新增)
tests/user-docs/validate-user-docs.py                        (新增)
tests/preflight/test-user-docs.sh                            (新增)
docs/plans/baselines/user-docs-baseline.json                 (新增)
docs/plans/stage-reports/W6-DOC1-user-docs-report.md         (本檔)
```

（VERSION bump 同步更新多個 baseline JSON 之 `version` 欄位，屬既有 bump 行為。）

## 技術備註（治本）

1. **DOC0+DOC1 合併**：依 `strawwu-user-docs-plan.md`，本 stage 同時交付目錄索引與安裝／救援指南，避免空索引。
2. **雙格式來源**：Markdown 為維護來源；HTML 由 `render-html.py` 產生，preflight 強制同步，利於 hermes-deliver 上傳。
3. **延後範圍誠實標示**：DOC2（wincompat 分級）、DOC3（完整 rollback）、w8-doc-handbook 明確標為後續 Wave，不擴 scope。
4. **支援渠道**：Hub bug-reporter 已文件化；論壇/Matrix/Discord 僅 TBD 佔位，符合 deferred scope §4。

## 已知限制 / 後續 Wave

| 項目 | 狀態 |
|------|------|
| Windows compat 分級使用者說明 | DOC2 / W7+ |
| `strawwu-upgrade --rollback` 操作手冊 | UPG5 |
| 完整使用者＋管理員手冊 | w8-doc-handbook |
| 官方支援 URL 實際連結 | v1.0 |
| HTML 上傳 hermes-deliver CDN | Hermes 部署步驟 |

## VERSION

`0.4.1.39` → `0.4.1.40`（iterate）

## 建議 commit message

```
feat(w6): add install/rescue user docs with HTML deliverables

- docs/user index + install-guide + rescue-guide (zh_TW)
- render-html.py + validate-user-docs.py + preflight gate
- smoke-live physical workflow documented (W6-HW1 follow-up)
Tests: make test-user-docs PASS, make preflight PASS
Version: 0.4.1.40
```

## Hermes 標記

| 時間 | 事件 |
|------|------|
| 2026-07-05 23:03 | `[worker-START]` companion supervisor 階段 37/47 w6-doc1-user-docs |
| 2026-07-05 23:09 | 初驗：`make test-user-docs` + `make preflight` exit 0 |
| 2026-07-05 23:18 | `[worker-TICK]` Hermes companion check status=IN_PROGRESS |
| 2026-07-05 23:22 | `[worker-DONE]` TICK 重驗：`make test-user-docs` + `make preflight` exit 0 — 待 Hermes mark PASS |

## 下一步

**w7-re-manifest-gpg**（Hermes mark PASS 後自動啟動，勿問使用者）。

## 續跑狀態

無阻塞。若需重跑驗證：

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-user-docs
make preflight
```

HTML 重新產生：`python3 tests/user-docs/render-html.py`
