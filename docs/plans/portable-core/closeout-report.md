# Portable Core A+3 — Closeout 報告

| 項目 | 值 |
|------|-----|
| Track | A+3（核心範圍 + 跨發行版包裝） |
| 階段 | `pc5-closeout`（6/6） |
| 分支 | `portable-core-a3` → `main` |
| 工作區 | `/mnt/data/code/project/StrawCoding/StrawWU-portable` |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 鎖序結果

| Stage | 證據 | 狀態 |
|-------|------|------|
| pc0-portable-scaffold | `docs/plans/portable-core/` + packaging README | PASS |
| pc1-self-contained-prefix | `tests/portable/output/smoke-prefix.json` | PASS |
| pc2-appimage | `smoke-appimage.json` + `SHA256SUMS` | PASS |
| pc3-flatpak | `smoke-flatpak.json`（誠實 PARTIAL） | PARTIAL |
| pc4-cross-distro-smoke | `matrix.json`（≥3 distros） | PASS |
| pc5-closeout | `closeout.json` | 本階段 |

## 交付物

| 類型 | 路徑 |
|------|------|
| 計畫 | `docs/plans/portable-core/A3-cross-distro-core.md` |
| Inventory | `docs/plans/portable-core/inventory.json` |
| 使用者指南 | `docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md` |
| 產物索引 | `docs/plans/portable-core/artifacts.json` |
| SHA256 | `tests/portable/output/SHA256SUMS` |
| Closeout 證據 | `tests/portable/output/closeout.json` |
| HTML | `docs/plans/portable-core/html/portable-closeout-report.html` |
| Packaging | `components/packaging/portable/` |

## 誠實標記

- Flatpak：**PARTIAL**（PE／SubsystemSession 需 `--filesystem=host`）
- **不宣稱**完整 Windows 相容
- **未改** ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- **未使用** Wine／Proton 底層、WinBox 命名
- 主 ISO／T1 工作區並行、未搶 build

## 驗收

```bash
bash tests/portable/closeout.sh
test -f tests/portable/output/closeout.json
jq -e '.status == "PASS"' tests/portable/output/closeout.json
```
