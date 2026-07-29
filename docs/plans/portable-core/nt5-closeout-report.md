# StrawNT 優玩 — Closeout 報告

| 項目 | 值 |
|------|-----|
| 產品 | **StrawNT** |
| Track | 優玩（nt0–nt5） |
| 階段 | `nt5-youwan-closeout` |
| 分支 | `main` |
| 工作區 | `/mnt/data/code/project/StrawCoding/StrawNT` |
| 執行層 | 自研 **native PE**／`execution_backend=native` |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 鎖序結果

| Stage | 證據 | 狀態 |
|-------|------|------|
| nt0-rebrand-disconnect | `tests/strawnt/output/nt0-rebrand.json` | PASS（更名 StrawNT、斷開 StrawWU 產品敘事） |
| nt1-real-graphics | `nt1-graphics.json` | PASS（真實 present／triangle；非 simulated） |
| nt2-real-light-games | `nt2-light-games.json` | PASS（≥2 真實輕量 Win demo；`real_binaries=true`） |
| nt3-real-launchers | `nt3-launchers.json` | **PARTIAL**（真實啟動器／商店 PE 僅驗啟動） |
| nt4-anticheat-honest | `nt4-anticheat.json` | **PARTIAL**（EAC/BE/Vanguard/CustomAC 探測矩陣；禁排位宣稱） |
| nt5-youwan-closeout | `nt5-closeout.json` | 本階段 |

跨發行版 smoke：`tests/portable/output/matrix.json`（≥3 發行版容器；非實機 ISO）。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/NT5-youwan-closeout.md` |
| 使用者指南 | `docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md` |
| README | `README.md`（StrawNT；native 預設；優玩誠實邊界） |
| 產物索引 | `docs/plans/portable-core/artifacts.json` |
| SHA256 | `tests/portable/output/SHA256SUMS` |
| AppImage／portable.tar.gz | `components/packaging/portable/appimage/dist/StrawNT-*-x86_64.*` |
| Closeout 報告／HTML | 本檔 + `html/nt5-closeout-report.html` |
| 證據 | `tests/strawnt/output/nt5-closeout.json` |

## 誠實標記（強制）

- **nt3 launchers = PARTIAL**：僅驗啟動器／安裝包啟動鏈；**不**保證遊戲本體完整暢玩
- **nt4 anticheat = PARTIAL**：探測矩陣與 grade（含 Vanguard **F**）；**禁止**宣稱排位／反作弊官方通過
- **不宣稱**完整 Windows 相容／3A 全開
- **未使用** Wine／Proton 底層；產品路徑預設 `execution_backend=native`
- **未改** ISO／os-image／Plymouth／Calamares／kernel／桌面 session／StrawWU 工作區
- **未使用** WinBox 命名
- GitHub Release 文案必須描述 **StrawNT／native PE** 與上述誠實邊界

## 跨發行版 smoke

```bash
make test-portable-matrix
jq .status tests/portable/output/matrix.json
```

沿用容器矩陣（Ubuntu 24.04、Fedora 41、Arch）；**非**實機 Live USB／ISO 戰役。

## 驗收

```bash
bash tests/strawnt/nt5-youwan-closeout.sh
test -f tests/strawnt/output/nt5-closeout.json
jq -e '.status == "PASS"' tests/strawnt/output/nt5-closeout.json
jq -e '.product == "StrawNT" or .name == "StrawNT"' tests/strawnt/output/nt5-closeout.json
rg -n 'StrawNT' README.md
```

最終驗收由 Hermes `trigger-verify` + `mark`；worker 不自宣稱最終 PASS。
