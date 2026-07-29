# Portable Native PE Real Exec — Closeout 報告

| 項目 | 值 |
|------|-----|
| Track | Native PE Real Exec（pe0–pe7） |
| 階段 | `pe7-closeout`（14/14；鎖序 pe0–pe7） |
| 分支 | `main` |
| 工作區 | `/mnt/data/code/project/StrawCoding/StrawWU-portable` |
| 執行層 | 自研 **strawwu-nt**／`execution_backend=native` |
| 結果 | **待 Hermes mark**（worker 不自宣稱最終 PASS） |

## 鎖序結果

| Stage | 證據 | 狀態 |
|-------|------|------|
| pe0-remove-wine | `tests/portable/output/pe0-remove-wine.json` | PASS |
| pe1-real-cpu-exec | `pe-real-exec.json`（mode=real 副作用） | PASS |
| pe2-win32-console-mvp | `pe-console.json` | PASS |
| pe3-gui-user32-mvp | `pe-gui.json` | PASS |
| pe4-installer-real | `pe-installer.json` | PASS |
| pe5-desktop-click | `pe-desktop-click.json` | PASS |
| pe6-golden-smoke | `pe-golden.json` | **PARTIAL**（誠實；公開 PE 已載入／CPU 執行，完整 CLI 副作用仍待加深） |
| pe7-closeout | `pe-closeout.json` | 本階段 |

包裝軌道（前序 pc0–pc5）仍可追溯：`closeout.json`、`matrix.json`、`smoke-*.json`。

## 交付物

| 類型 | 路徑 |
|------|------|
| Kickoff | `docs/plans/kickoff/PE7-closeout.md` |
| 使用者指南 | `docs/plans/portable-core/USER-GUIDE.md`、`docs/user/portable-guide.md` |
| README | `README.md`（native 預設；無 Wine 安裝指引） |
| 產物索引 | `docs/plans/portable-core/artifacts.json` |
| SHA256 | `tests/portable/output/SHA256SUMS` |
| AppImage／portable.tar.gz | `components/packaging/portable/appimage/dist/` |
| Closeout 報告／HTML | 本檔 + `html/pe-closeout-report.html` |
| 證據 | `tests/portable/output/pe-closeout.json` |

## 誠實標記

- **pe6 golden = PARTIAL**：7za／BusyBox 經 native 載入與 CPU 執行迴圈有證據；完整 CRT／CLI 功能性副作用尚未觀測 — **不**改寫成 PASS
- **不宣稱**完整 Windows 相容／反作弊通過
- **未使用** Wine／Proton 底層；產品路徑無 `ensure_wine`／`wine_backend`／`STRAWWU_BACKEND=wine`
- **未改** ISO／os-image／Plymouth／Calamares／kernel／桌面 session
- **未使用** WinBox 命名
- GitHub Release 文案必須描述 **native／strawwu-nt**（取代曾誤發的 Wine 預設 Release）

## 驗收

```bash
bash tests/portable/pe-closeout.sh
test -f tests/portable/output/pe-closeout.json
jq -e '.status == "PASS"' tests/portable/output/pe-closeout.json
```

最終驗收由 Hermes `trigger-verify` + `mark`；worker 不自宣稱最終 PASS。
