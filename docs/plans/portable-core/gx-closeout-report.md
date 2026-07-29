# Portable Game Compat — Closeout 報告

| 項目 | 值 |
|------|-----|
| Track | Game Compat（gx0–gx5） |
| 階段 | `gx5-closeout`（20/20；鎖序 gx0–gx5） |
| 分支 | `main` |
| 工作區 | `/mnt/data/code/project/StrawCoding/StrawWU-portable` |
| 執行層 | 自研 **strawwu-nt**／`execution_backend=native` |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 鎖序結果

| Stage | 證據 | 狀態 |
|-------|------|------|
| gx0-graphics-vk-gl | `tests/portable/output/gx-graphics.json` | PASS（DXGI/D3D11→VK + wgl→GL present／triangle） |
| gx1-audio-input | `gx-audio-input.json` | PASS（WASAPI→PipeWire/ALSA + 輸入路徑） |
| gx2-light-2d3d | `gx-light-games.json` | PASS（≥2 輕量 2D/3D；apps 內可含誠實 PARTIAL） |
| gx3-launcher-smoke | `gx-launchers.json` | **PARTIAL**（Steam／Epic／三角洲級啟動器僅驗啟動） |
| gx4-anticheat-matrix | `gx-anticheat.json` | **PARTIAL**（EAC/BE/Vanguard 探測矩陣；grade A/B/C/F） |
| gx5-closeout | `gx-closeout.json` | 本階段 |

包裝／Native PE 前序仍可追溯：`closeout.json`、`pe-closeout.json`、`matrix.json`。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/GX5-closeout.md` |
| 使用者指南 | `docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md` |
| README | `README.md`（native 預設；Game Compat 誠實邊界） |
| 產物索引 | `docs/plans/portable-core/artifacts.json` |
| SHA256 | `tests/portable/output/SHA256SUMS` |
| AppImage／portable.tar.gz | `components/packaging/portable/appimage/dist/` |
| Closeout 報告／HTML | 本檔 + `html/gx-closeout-report.html` |
| 證據 | `tests/portable/output/gx-closeout.json` |

## 誠實標記（強制）

- **gx3 launchers = PARTIAL**：僅驗啟動器／登入 UI 啟動鏈；**不**保證遊戲本體完整暢玩
- **gx4 anticheat = PARTIAL**：探測矩陣與 grade（含 Vanguard **F**）；**禁止**宣稱排位／反作弊官方通過
- **不宣稱**完整 Windows 相容／3A 全開
- **未使用** Wine／Proton 底層；產品路徑無 `ensure_wine`／`wine_backend`／`STRAWWU_BACKEND=wine`
- **未改** ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- **未使用** WinBox 命名
- GitHub Release 文案必須描述 **native／strawwu-nt** 與上述誠實邊界

## 跨發行版 smoke（可複用）

沿用 `tests/portable/smoke-matrix.sh` → `tests/portable/output/matrix.json`（≥3 發行版容器；非實機 ISO）。

## 驗收

```bash
bash tests/portable/gx-closeout.sh
test -f tests/portable/output/gx-closeout.json
jq -e '.status == "PASS"' tests/portable/output/gx-closeout.json
```

最終驗收由 Hermes `trigger-verify` + `mark`；worker 不自宣稱最終 PASS。
