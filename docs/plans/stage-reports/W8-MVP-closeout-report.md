# W8-MVP closeout 階段報告

| 任務 | w8-mvp-closeout |
|------|-----------------|
| 版本 | 0.5.0.9 |
| 日期 | 2026-07-06 |
| Worker | 階段 47/47（w8-mvp-closeout） |
| 最後驗證 | 2026-07-06T04:42 UTC-4（階段 47 worker companion 終驗） |
| 結果 | **待 Hermes mark**（worker 不自宣稱 PASS） |

## 目標

Wave 8 MVP Closeout — `test-wave-all-pass` + MVP DoD 驗證 + HTML hermes-deliver 報告；彙整 47 Wave 階段證據，銜接 Post-MVP（u26-m1-base-clone）。

## 交付物

| 類型 | 路徑 |
|------|------|
| MVP DoD 文件 | `docs/plans/mvp-closeout/mvp-dod.md` |
| HTML（hermes-deliver） | `docs/plans/mvp-closeout/html/mvp-closeout-report.html` |
| HTML 渲染器 | `tests/mvp-closeout/render-html.py` |
| 驗證腳本 | `tests/mvp-closeout/validate-mvp-closeout.py` |
| Preflight gate | `tests/preflight/test-mvp-closeout.sh` |
| baseline JSON | `docs/plans/baselines/mvp-closeout-baseline.json` |
| Wave 狀態 | `docs/plans/baselines/wave-status.json` |
| Makefile | `test-mvp-closeout`；`preflight` 串接 |
| VERSION | `0.5.0.9` |

## MVP DoD 摘要（PRD §5）

| # | 項目 | 證據 baseline / stage |
|---|------|----------------------|
| 1 | StrawWU 全程品牌 | legal-baseline、W5-I3 |
| 2 | Flathub 預設、無 Snap | nosnap-audit、target-flathub-baseline |
| 3 | bug-reporter + Hub | desktop-baseline、hub-settings |
| 4 | calamares + firstboot | firstboot-baseline、install-firstboot-e2e |
| 5 | shell/session 最小可用 | shell-baseline、greeter-session |
| 6 | App Registry list/remove | apps-page、deep-uninstall |
| 7 | Win compat GUI E2E | wincompat-e2e-baseline |
| 8 | release-iso + SHA256 + E2E | release-manifest、installed-boot |

延後範圍（多使用者、備份、社群、插件 API）依 `strawwu-deferred-scope.md` **不 blocking** closeout。

## 驗收命令輸出

### `make test-mvp-closeout` — exit 0

Log: `/tmp/w8-mvp-test-mvp-closeout.log`

```
=== W8-MVP closeout validation ===
（全 40 項 PASS：PRD DoD 覆蓋、15 baseline、wave-status 47 stages、47 stage reports、HTML Teal hermes-deliver）
=== W8-MVP closeout validation: PASS ===
```

### `make test-wave-all-pass` — exit 1（預期，待 Hermes mark）

Log: `/tmp/w8-mvp-test-wave-all-pass.log`

```
Wave status: 46/47 PASS
  [FAIL] w8-mvp-closeout: IN_PROGRESS
```

Hermes mark `w8-mvp-closeout` PASS 後應輸出 `ALL WAVE STAGES PASS` 並 exit 0。

### `make preflight` — exit 0（~135s）

Log: `/tmp/w8-mvp-preflight.log`

含 W0–W8 全部階段 + **W8-MVP closeout** 終行：`=== W8-MVP closeout done: PASS ===`；末行 `POST-MVP INFRASTRUCTURE OK`（134.6s）。

修復：`tests/preflight/test-initramfs-hooks.sh` 改為快取 `dpkg-deb -c` 輸出，避免 `pipefail` + `grep -q` SIGPIPE 偶發 FAIL。

## 變更檔案清單

```
docs/plans/mvp-closeout/mvp-dod.md                          (新增)
docs/plans/mvp-closeout/html/mvp-closeout-report.html       (新增，渲染產物)
tests/mvp-closeout/render-html.py                           (新增)
tests/mvp-closeout/validate-mvp-closeout.py                 (新增)
tests/preflight/test-mvp-closeout.sh                        (新增)
docs/plans/baselines/mvp-closeout-baseline.json               (新增)
docs/plans/stage-reports/W8-MVP-closeout-report.md            (本檔)
Makefile                                                    (test-mvp-closeout + preflight)
tests/preflight/test-initramfs-hooks.sh                     (pipefail 穩定性修復)
VERSION                                                     (0.5.0.8 → 0.5.0.9)
```

## 設計決策

1. **獨立 closeout gate**：`test-mvp-closeout` 驗證 PRD DoD + 15 項 baseline + 47 stage reports + HTML，不依賴 Hermes mark。
2. **`test-wave-all-pass` 分離**：讀取 Hermes `state.json`；closeout stage 由 Hermes 最終 mark，worker 不自宣稱全 Wave PASS。
3. **HTML 風格**：沿用 W6-DOC1 / W8-DOC handbook Teal `#14b8a6` 深色 hermes-deliver 模板。

## 建議 Hermes 驗收

```bash
cd /mnt/data/code/project/StrawCoding/StrawWU
make test-mvp-closeout    # 應 exit 0
make preflight            # 應 exit 0（含 W8-MVP closeout 終行）
make test-wave-all-pass   # mark PASS 後應 exit 0
```

## 下一步

Hermes mark PASS → **MVP 全 Wave PASS** → 自動啟動 `u26-m1-base-clone`（Ubuntu 26.04 遷移，勿問使用者）。

## Commit message（建議）

```
feat(w8): MVP closeout DoD gate + HTML report

- mvp-dod.md + hermes-deliver HTML + validate/preflight scripts
- Makefile test-mvp-closeout; preflight chain extended
- VERSION 0.5.0.9
Tests: make test-mvp-closeout; make preflight; make test-wave-all-pass (post-mark)
Issue: w8-mvp-closeout v0.5.0.9
```

HTML 重新產生：`python3 tests/mvp-closeout/render-html.py`
